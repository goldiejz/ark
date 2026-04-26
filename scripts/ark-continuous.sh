#!/usr/bin/env bash
# ark-continuous.sh — Phase 7 AOS daemon: INBOX consumer + tick loop
#
# Plan 07-02 (REQ-AOS-40, REQ-AOS-41) — main daemon body.
#
# Sources:
#   scripts/ark-policy.sh      — single-writer audit (`_policy_log`)
#   scripts/lib/inbox-parser.sh — frontmatter parse + intent dispatch
#   scripts/ark-escalations.sh — `ark_escalate` queue writer
#   scripts/lib/policy-config.sh — cascading config (via ark-policy.sh)
#
# Public API (sourceable lib + CLI guard):
#   continuous_acquire_lock          mkdir-style lock at $LOCK_DIR; trap on EXIT cleans up.
#   continuous_release_lock          rmdir lock (idempotent).
#   continuous_check_daily_cap       0=PROCEED, 1=SUSPENDED; echoes USED=N CAP=M to stderr.
#   continuous_process_inbox <file>  Lifecycle one INBOX file (parse → dispatch → mv/rename).
#   continuous_record_failure        Bumps fail-counter; auto-creates PAUSE at 3 consecutive.
#   continuous_record_success        Resets fail-counter.
#   continuous_tick                  Single tick orchestrator (the cron entrypoint).
#   continuous_self_test             12+ assertions in mktemp -d isolation.
#
# Audit decisions emitted by this file (class:continuous):
#   TICK_START | TICK_COMPLETE | INBOX_DISPATCH | INBOX_PROCESSED | INBOX_FAILED |
#   INBOX_MALFORMED | DAILY_CAP_HIT | LOCK_CONTENDED | PAUSE_ACTIVE | AUTO_PAUSE_3_FAIL
# Decisions deferred to other plans:
#   STUCK_PHASE_DETECTED, AUTO_PAUSED  — Plan 07-03 (health-monitor)
#   WEEKLY_DIGEST_WRITTEN              — Plan 07-06 (separate script)
#
# Bash 3 compat (macOS): no `declare -A`, no `mapfile`, no `${var,,}`.
# IMPORTANT: Sourceable library — does NOT set -e/-u/-o pipefail at file scope.

# === Paths (resolve via ARK_HOME so self-test can isolate) ===
VAULT_PATH="${ARK_HOME:-$HOME/vaults/ark}"
INBOX_DIR="$VAULT_PATH/INBOX"
LOCK_DIR="$VAULT_PATH/.continuous.lock"
PAUSE_FILE="$VAULT_PATH/PAUSE"
FAIL_COUNT_FILE="$VAULT_PATH/.continuous-fail-count"
CONTINUOUS_LOG="$VAULT_PATH/observability/continuous-operation.log"
ESCALATIONS_FILE="$VAULT_PATH/ESCALATIONS.md"

# === Source dependencies (graceful degradation) ===
_ARK_CONTINUOUS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

# shellcheck disable=SC1091
if [[ -f "$_ARK_CONTINUOUS_DIR/ark-policy.sh" ]]; then
  # ark-policy.sh sources policy-config.sh + policy-db.sh internally
  source "$_ARK_CONTINUOUS_DIR/ark-policy.sh"
else
  # Stub: log to stderr only
  _policy_log() { echo "[stub _policy_log] class=$1 decision=$2 reason=$3" >&2; echo "stub-id"; }
  policy_config_get() { echo "$2"; }
fi

# shellcheck disable=SC1091
if [[ -f "$_ARK_CONTINUOUS_DIR/lib/inbox-parser.sh" ]]; then
  source "$_ARK_CONTINUOUS_DIR/lib/inbox-parser.sh"
else
  inbox_parse_frontmatter() { echo "inbox-parser.sh missing" >&2; return 2; }
  inbox_validate_intent()   { return 1; }
  inbox_dispatch_intent()   { return 1; }
fi

# shellcheck disable=SC1091
if [[ -f "$_ARK_CONTINUOUS_DIR/ark-escalations.sh" ]]; then
  source "$_ARK_CONTINUOUS_DIR/ark-escalations.sh"
else
  ark_escalate() { echo "[stub ark_escalate] $*" >&2; return 1; }
fi

# === Internal: reset paths after ARK_HOME changes (used by self-test) ===
_continuous_refresh_paths() {
  VAULT_PATH="${ARK_HOME:-$HOME/vaults/ark}"
  INBOX_DIR="$VAULT_PATH/INBOX"
  LOCK_DIR="$VAULT_PATH/.continuous.lock"
  PAUSE_FILE="$VAULT_PATH/PAUSE"
  FAIL_COUNT_FILE="$VAULT_PATH/.continuous-fail-count"
  CONTINUOUS_LOG="$VAULT_PATH/observability/continuous-operation.log"
  ESCALATIONS_FILE="$VAULT_PATH/ESCALATIONS.md"
}

# === Internal: ensure observability log directory + file exist ===
_continuous_ensure_log() {
  local dir
  dir="$(dirname "$CONTINUOUS_LOG")"
  mkdir -p "$dir" 2>/dev/null
  [[ -f "$CONTINUOUS_LOG" ]] || : > "$CONTINUOUS_LOG"
}

# === continuous_acquire_lock — mkdir-style lock ===
# Returns 0 if acquired, 1 if contended.
continuous_acquire_lock() {
  mkdir -p "$VAULT_PATH" 2>/dev/null
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    # Trap installed by caller (continuous_tick) so we don't leak across nested calls.
    return 0
  fi
  return 1
}

# === continuous_release_lock — idempotent rmdir ===
continuous_release_lock() {
  rmdir "$LOCK_DIR" 2>/dev/null || true
}

# === continuous_check_daily_cap ===
# Returns 0 if USED < CAP (PROCEED), 1 if exceeded (SUSPENDED).
# Echoes "USED=N CAP=M" to stderr for caller-side logging.
continuous_check_daily_cap() {
  local cap used
  cap=$(policy_config_get continuous.daily_token_cap 50000 2>/dev/null)
  [[ -z "$cap" ]] && cap=50000

  used=0
  # Try SQLite first via db_path() if available
  if type db_path >/dev/null 2>&1; then
    local dbp
    dbp="$(db_path 2>/dev/null)"
    if [[ -f "$dbp" ]]; then
      # Sum tokens from class IN ('budget','dispatch') for today (UTC).
      # CONTEXT.md D-CONT-DAILY-CAP — coarse approximation; truth is the audit log.
      local q="SELECT IFNULL(SUM(json_extract(context,'\$.tokens')),0) FROM decisions WHERE class IN ('budget','dispatch','dispatcher') AND ts >= date('now','start of day');"
      used=$(sqlite3 "$dbp" "$q" 2>/dev/null)
      [[ -z "$used" ]] && used=0
    fi
  fi

  # Coerce to integer (sqlite may return floats)
  used=${used%.*}
  [[ "$used" =~ ^[0-9]+$ ]] || used=0

  echo "USED=$used CAP=$cap" >&2
  if [[ "$used" -ge "$cap" ]]; then
    return 1
  fi
  return 0
}

# === continuous_record_failure ===
# Bumps a per-vault failure counter. If counter reaches 3, auto-creates PAUSE,
# fires AUTO_PAUSE_3_FAIL audit, and queues a repeated-failure escalation.
# Idempotent: if PAUSE already exists, no double-escalate.
continuous_record_failure() {
  local count=0
  if [[ -f "$FAIL_COUNT_FILE" ]]; then
    count=$(cat "$FAIL_COUNT_FILE" 2>/dev/null || echo 0)
    [[ "$count" =~ ^[0-9]+$ ]] || count=0
  fi
  count=$((count + 1))
  echo "$count" > "$FAIL_COUNT_FILE"

  if [[ "$count" -ge 3 ]] && [[ ! -f "$PAUSE_FILE" ]]; then
    : > "$PAUSE_FILE"
    _policy_log "continuous" "AUTO_PAUSE_3_FAIL" \
      "consecutive_failures=$count" \
      "{\"fail_count\":$count}" \
      >/dev/null 2>&1
    ark_escalate "repeated-failure" \
      "ark-continuous: $count consecutive failure ticks → auto-paused" \
      "Daemon ticks failed $count consecutive times. PAUSE file auto-created at $PAUSE_FILE. Investigate INBOX/.failed files and observability/continuous-operation.log, then \`ark continuous resume\`." \
      >/dev/null 2>&1 || true
  fi
}

# === continuous_record_success — reset fail counter ===
continuous_record_success() {
  rm -f "$FAIL_COUNT_FILE" 2>/dev/null || true
}

# === Internal: append a markdown entry to ESCALATIONS.md (single-writer route) ===
# Uses ark_escalate when available; never touches the file directly.
_continuous_queue_failure() {
  local file="$1"
  local intent="$2"
  local rc="$3"
  ark_escalate "repeated-failure" \
    "ark-continuous: dispatch failed for $(basename "$file")" \
    "Intent: $intent
Exit code: $rc
File renamed to ${file%.md}.failed
Inspect $CONTINUOUS_LOG for the dispatch transcript." \
    >/dev/null 2>&1 || true
}

# === continuous_process_inbox <file> ===
# Returns 0 on successful dispatch + archive; 1 on malformed/failed.
continuous_process_inbox() {
  local file="$1"
  if [[ -z "$file" ]] || [[ ! -f "$file" ]]; then
    echo "continuous_process_inbox: file not found: $file" >&2
    return 1
  fi
  _continuous_ensure_log

  local fname
  fname="$(basename "$file")"

  # 1. Parse frontmatter
  local parsed
  parsed=$(inbox_parse_frontmatter "$file" 2>/dev/null)
  local prc=$?
  if [[ "$prc" -ne 0 ]]; then
    # Malformed → rename in place
    mv "$file" "${file%.md}.malformed" 2>/dev/null || true
    _policy_log "continuous" "INBOX_MALFORMED" \
      "no_frontmatter_or_missing_intent" \
      "{\"file\":\"$fname\"}" \
      >/dev/null 2>&1
    return 1
  fi

  # 2. Eval parsed assignments into local scope
  local INTENT="" CUSTOMER="" PRIORITY="" DESC="" PROJECT="" PHASE=""
  local line key val
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    key="${line%%=*}"
    val="${line#*=}"
    case "$key" in
      INTENT)   INTENT="$val" ;;
      CUSTOMER) CUSTOMER="$val" ;;
      PRIORITY) PRIORITY="$val" ;;
      DESC)     DESC="$val" ;;
      PROJECT)  PROJECT="$val" ;;
      PHASE)    PHASE="$val" ;;
    esac
  done <<EOF
$parsed
EOF

  # 3. Validate intent
  if ! inbox_validate_intent "$INTENT" 2>/dev/null; then
    mv "$file" "${file%.md}.malformed" 2>/dev/null || true
    _policy_log "continuous" "INBOX_MALFORMED" \
      "unknown_intent:$INTENT" \
      "{\"file\":\"$fname\",\"intent\":\"$INTENT\"}" \
      >/dev/null 2>&1
    return 1
  fi

  # 4. Build dispatch command
  local cmd
  cmd=$(inbox_dispatch_intent "$INTENT" "$CUSTOMER" "$PRIORITY" "$DESC" "$PHASE" 2>/dev/null)
  local drc=$?
  if [[ "$drc" -ne 0 ]] || [[ -z "$cmd" ]]; then
    mv "$file" "${file%.md}.failed" 2>/dev/null || true
    _policy_log "continuous" "INBOX_FAILED" \
      "dispatch_build_failed:$INTENT" \
      "{\"file\":\"$fname\",\"intent\":\"$INTENT\"}" \
      >/dev/null 2>&1
    _continuous_queue_failure "$file" "$INTENT" "$drc"
    return 1
  fi

  # 5. Audit DISPATCH (pre-eval)
  _policy_log "continuous" "INBOX_DISPATCH" \
    "intent=$INTENT customer=$CUSTOMER" \
    "{\"file\":\"$fname\",\"intent\":\"$INTENT\",\"customer\":\"$CUSTOMER\",\"priority\":\"$PRIORITY\"}" \
    >/dev/null 2>&1

  # 6. Eval dispatch command (in subshell), capturing transcript to log.
  # Honor ARK_CREATE_GITHUB invariant: do not set it here. Caller environment governs.
  local rc=0
  (
    set +e
    eval "$cmd"
    exit $?
  ) >> "$CONTINUOUS_LOG" 2>&1
  rc=$?

  if [[ "$rc" -eq 0 ]]; then
    # Success → move to processed/<UTC-date>/
    local today
    today=$(date -u +%Y-%m-%d)
    local destdir="$INBOX_DIR/processed/$today"
    mkdir -p "$destdir" 2>/dev/null
    mv "$file" "$destdir/" 2>/dev/null || true
    _policy_log "continuous" "INBOX_PROCESSED" \
      "intent:$INTENT" \
      "{\"file\":\"$fname\",\"customer\":\"$CUSTOMER\",\"intent\":\"$INTENT\"}" \
      >/dev/null 2>&1
    return 0
  else
    # Failure → rename .failed + escalate
    mv "$file" "${file%.md}.failed" 2>/dev/null || true
    _policy_log "continuous" "INBOX_FAILED" \
      "exit:$rc intent:$INTENT" \
      "{\"file\":\"$fname\",\"intent\":\"$INTENT\",\"exit\":$rc}" \
      >/dev/null 2>&1
    _continuous_queue_failure "$file" "$INTENT" "$rc"
    return 1
  fi
}

# === continuous_tick — single tick orchestrator ===
# Returns 0 on success (including PAUSE/cap/lock skip); non-zero only on
# infrastructure failure. Business outcomes are audit rows, not exit codes.
continuous_tick() {
  _continuous_refresh_paths

  # 1. PAUSE check (BEFORE lock, so PAUSE is honored even if a stale lock exists)
  if [[ -f "$PAUSE_FILE" ]]; then
    _policy_log "continuous" "PAUSE_ACTIVE" \
      "pause_file_present" \
      "{\"pause_file\":\"$PAUSE_FILE\"}" \
      >/dev/null 2>&1
    return 0
  fi

  # 2. Acquire lock
  if ! continuous_acquire_lock; then
    _policy_log "continuous" "LOCK_CONTENDED" \
      "another_tick_in_progress" \
      "{\"lock\":\"$LOCK_DIR\"}" \
      >/dev/null 2>&1
    return 0
  fi

  # Trap to release lock on any exit path (including SIGINT/SIGTERM/error).
  # shellcheck disable=SC2064
  trap "continuous_release_lock" EXIT INT TERM

  _continuous_ensure_log
  _policy_log "continuous" "TICK_START" "tick_began" "null" >/dev/null 2>&1

  # 3. Daily cap check
  if ! continuous_check_daily_cap 2>/dev/null; then
    _policy_log "continuous" "DAILY_CAP_HIT" \
      "daily_token_cap_exceeded" \
      "null" \
      >/dev/null 2>&1
    continuous_release_lock
    trap - EXIT INT TERM
    return 0
  fi

  # 4. Scan INBOX
  local processed=0 failed=0 malformed=0
  if [[ -d "$INBOX_DIR" ]]; then
    # Bash 3 compat: while read with null-safe-ish find output
    local f
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      [[ ! -f "$f" ]] && continue
      # Pre-check parse to classify malformed before lifecycle wrapper runs
      local pre
      pre=$(inbox_parse_frontmatter "$f" 2>/dev/null)
      local pprc=$?
      if [[ "$pprc" -ne 0 ]]; then
        continuous_process_inbox "$f" >/dev/null 2>&1
        malformed=$((malformed + 1))
        continue
      fi
      if continuous_process_inbox "$f" >/dev/null 2>&1; then
        processed=$((processed + 1))
      else
        # Distinguish malformed-after-parse (unknown intent) vs failed dispatch.
        # Re-detect by suffix of the now-renamed file.
        if [[ -f "${f%.md}.malformed" ]]; then
          malformed=$((malformed + 1))
        else
          failed=$((failed + 1))
        fi
      fi
    done < <(find "$INBOX_DIR" -maxdepth 1 -type f -name '*.md' 2>/dev/null)
  fi

  # 5. Update fail counter (success if no failures this tick)
  if [[ "$failed" -gt 0 ]]; then
    continuous_record_failure
  else
    continuous_record_success
  fi

  # 6. SECTION sentinel: health-monitor (Plan 07-03 fills in)
  # === SECTION: health-monitor (Plan 07-03) ===
  # Body added by Plan 07-03. Implements:
  #   continuous_health_monitor      — stuck-phase detection per project under
  #     $ARK_PORTFOLIO_ROOT (STATE.md mtime > 24h AND no commits in last 24h).
  #     correlation_id="<slug>:<phase>"; logs STUCK_PHASE_DETECTED. When 3+
  #     consecutive detections seen for same correlation_id within 60min AND
  #     no STUCK_ESCALATED in last 24h, append ESCALATIONS via ark_escalate
  #     (architectural-ambiguity class) and log STUCK_ESCALATED.
  #   continuous_auto_pause_check    — inspects last 3 TICK_COMPLETE rows; if
  #     all show f:N>0, touch PAUSE + log AUTO_PAUSED + escalate. Idempotent
  #     (no-op if PAUSE already exists).
  # Both functions are defined here so they live entirely within the sentinel
  # region (Plan 07-03's editable surface). Re-defining each tick is cheap.

  continuous_health_monitor() {
    local root="${ARK_PORTFOLIO_ROOT:-$HOME/code}"
    [[ ! -d "$root" ]] && return 0

    local dbp=""
    if type db_path >/dev/null 2>&1; then
      dbp="$(db_path 2>/dev/null)"
    fi

    local now state_md proj_dir slug phase state_mtime age stuck_mtime
    local last_commit_epoch git_age stuck_git corr_id ctx
    local count escalated_recently
    now=$(date +%s)

    # Walk to depth 3, find every project STATE.md (mirrors portfolio_scan_candidates).
    while IFS= read -r state_md; do
      [[ -z "$state_md" ]] && continue
      [[ ! -f "$state_md" ]] && continue
      proj_dir=$(dirname "$(dirname "$state_md")")
      slug=$(basename "$proj_dir")

      # Extract current phase value (quoted or bare).
      phase=$(grep -m1 '^current_phase:' "$state_md" 2>/dev/null \
        | sed -E 's/^current_phase:[[:space:]]*//; s/^"//; s/"$//' )
      [[ -z "$phase" ]] && phase="unknown"

      # mtime check (macOS stat -f %m; bash 3 compat)
      state_mtime=$(stat -f %m "$state_md" 2>/dev/null)
      [[ -z "$state_mtime" ]] && continue
      age=$(( now - state_mtime ))
      if [[ "$age" -gt 86400 ]]; then
        stuck_mtime=1
      else
        stuck_mtime=0
      fi

      # git commit recency (last 24h on whatever HEAD is)
      last_commit_epoch=$(cd "$proj_dir" 2>/dev/null && git log -1 --format=%ct 2>/dev/null)
      if [[ -z "$last_commit_epoch" ]]; then
        stuck_git=1
      else
        git_age=$(( now - last_commit_epoch ))
        if [[ "$git_age" -gt 86400 ]]; then
          stuck_git=1
        else
          stuck_git=0
        fi
      fi

      if [[ "$stuck_mtime" -eq 1 ]] && [[ "$stuck_git" -eq 1 ]]; then
        # NOTE: policy.db schema has correlation_id REFERENCES decisions(decision_id)
        # (self-FK chain pointer), so we cannot stuff slug:phase there. Instead the
        # group key is encoded in the `reason` field and queried via LIKE.
        corr_id="${slug}:${phase}"
        # JSON-safe phase (escape backslashes + double quotes)
        local phase_j slug_j
        phase_j=$(printf '%s' "$phase" | sed 's/\\/\\\\/g; s/"/\\"/g')
        slug_j=$(printf '%s' "$slug" | sed 's/\\/\\\\/g; s/"/\\"/g')
        ctx="{\"slug\":\"${slug_j}\",\"phase\":\"${phase_j}\",\"age\":${age},\"corr\":\"${corr_id}\"}"
        # reason format: "stuck:<slug>:<phase> age:NNN" — LIKE-friendly group key.
        _policy_log "continuous" "STUCK_PHASE_DETECTED" \
          "stuck:${corr_id} age:${age}" "$ctx" "null" >/dev/null 2>&1

        if [[ -n "$dbp" ]] && [[ -f "$dbp" ]]; then
          # Escape single quotes for SQL LIKE literal.
          local corr_sql
          corr_sql=$(printf '%s' "$corr_id" | sed "s/'/''/g")
          count=$(sqlite3 "$dbp" \
            "SELECT COUNT(*) FROM decisions WHERE class='continuous' AND decision='STUCK_PHASE_DETECTED' AND reason LIKE 'stuck:${corr_sql} %' AND ts >= datetime('now','-60 minutes');" \
            2>/dev/null)
          [[ -z "$count" ]] && count=0
          escalated_recently=$(sqlite3 "$dbp" \
            "SELECT COUNT(*) FROM decisions WHERE class='continuous' AND decision='STUCK_ESCALATED' AND reason LIKE 'stuck:${corr_sql} %' AND ts >= datetime('now','-24 hours');" \
            2>/dev/null)
          [[ -z "$escalated_recently" ]] && escalated_recently=0

          if [[ "$count" -ge 3 ]] && [[ "$escalated_recently" -eq 0 ]]; then
            ark_escalate "architectural-ambiguity" \
              "ark-continuous: stuck phase $slug ($phase) — $count consecutive detections" \
              "Project: $slug
Phase: $phase
STATE.md mtime age: ${age}s (> 24h)
No git commits on HEAD in last 24h.
Detected $count times within last 60 minutes.
Inspect $proj_dir/.planning/STATE.md and recent activity. Resume the phase or close it manually." \
              >/dev/null 2>&1 || true
            _policy_log "continuous" "STUCK_ESCALATED" \
              "stuck:${corr_id} consecutive:${count}" "$ctx" "null" >/dev/null 2>&1
          fi
        fi
      fi
    done < <(find "$root" -maxdepth 3 -type f -name STATE.md -path '*/.planning/STATE.md' 2>/dev/null)

    return 0
  }

  continuous_auto_pause_check() {
    # Idempotent: if PAUSE already exists, no-op.
    [[ -f "$PAUSE_FILE" ]] && return 0

    local dbp=""
    if type db_path >/dev/null 2>&1; then
      dbp="$(db_path 2>/dev/null)"
    fi
    [[ -z "$dbp" ]] || [[ ! -f "$dbp" ]] && return 0

    # Count last-3 TICK_COMPLETE rows whose reason has f:N>0.
    # Reason format from 07-02: "p:N f:M m:K". Match f:1, f:2, ..., f:9... (any non-zero).
    # Sort by ts THEN decision_id (unique random suffix) since ts has 1-second
    # resolution and rapid same-second ticks would otherwise tie-break arbitrarily.
    local last_3_failed
    last_3_failed=$(sqlite3 "$dbp" \
      "SELECT COUNT(*) FROM (SELECT reason FROM decisions WHERE class='continuous' AND decision='TICK_COMPLETE' ORDER BY ts DESC, rowid DESC LIMIT 3) WHERE reason GLOB '*f:[1-9]*';" \
      2>/dev/null)
    [[ -z "$last_3_failed" ]] && last_3_failed=0

    if [[ "$last_3_failed" -ge 3 ]]; then
      : > "$PAUSE_FILE"
      _policy_log "continuous" "AUTO_PAUSED" \
        "consecutive_failure_ticks:3" \
        "{\"trigger\":\"3_consecutive_failure_ticks\"}" \
        >/dev/null 2>&1
      ark_escalate "repeated-failure" \
        "ark-continuous: 3 consecutive failure-ticks → auto-paused" \
        "Last 3 TICK_COMPLETE audit rows all show non-zero failed count. PAUSE file created at $PAUSE_FILE. Inspect observability/continuous-operation.log + INBOX/*.failed before \`ark continuous resume\`." \
        >/dev/null 2>&1 || true
    fi
    return 0
  }

  continuous_health_monitor || true
  continuous_auto_pause_check || true
  # === END SECTION: health-monitor ===

  # 7. Audit TICK_COMPLETE
  _policy_log "continuous" "TICK_COMPLETE" \
    "p:$processed f:$failed m:$malformed" \
    "{\"processed\":$processed,\"failed\":$failed,\"malformed\":$malformed}" \
    >/dev/null 2>&1

  # 8. Release lock
  continuous_release_lock
  trap - EXIT INT TERM
  return 0
}

# === SECTION: subcommands (Plan 07-04) ===
# Body added by Plan 07-04. Implements:
#   continuous_install     — generate + load ~/Library/LaunchAgents/com.ark.continuous.plist
#   continuous_uninstall   — unload + remove plist
#   continuous_status      — show last tick, next tick, recent decisions, daily token used
#   continuous_pause       — touch PAUSE file
#   continuous_resume      — rm PAUSE file
#   continuous_plist_emit  — pure stdout plist generator (idempotent, byte-stable)
# === END SECTION: subcommands ===

# === continuous_self_test — 12+ assertions in mktemp -d isolation ===
continuous_self_test() {
  local pass=0 fail=0
  local TMP REAL_DB_MD5_BEFORE REAL_DB_MD5_AFTER

  TMP=$(mktemp -d 2>/dev/null) || { echo "mktemp failed"; return 1; }

  # Capture real-vault md5 invariant baseline (if real db exists).
  local real_db="${HOME}/vaults/ark/observability/policy.db"
  REAL_DB_MD5_BEFORE=""
  if [[ -f "$real_db" ]]; then
    REAL_DB_MD5_BEFORE=$(md5 -q "$real_db" 2>/dev/null || md5sum "$real_db" 2>/dev/null | awk '{print $1}')
  fi

  echo "🧪 ark-continuous.sh self-test (fixture: $TMP)"
  echo ""

  _ct_assert_eq() {
    local expected="$1" actual="$2" label="$3"
    if [[ "$expected" == "$actual" ]]; then
      echo "  ✅ $label"
      pass=$((pass+1))
    else
      echo "  ❌ $label  (expected: '$expected', got: '$actual')"
      fail=$((fail+1))
    fi
  }

  _ct_assert_true() {
    local cond_label="$2"
    if [[ "$1" == "1" ]]; then
      echo "  ✅ $cond_label"
      pass=$((pass+1))
    else
      echo "  ❌ $cond_label"
      fail=$((fail+1))
    fi
  }

  # Set up isolated environment.
  export ARK_HOME="$TMP/vault"
  export ARK_POLICY_DB="$TMP/vault/observability/policy.db"
  # Phase 07-03: portfolio root must also be isolated BEFORE first tick, otherwise
  # continuous_tick → continuous_health_monitor scans real ~/code and writes
  # STUCK_PHASE_DETECTED rows for real projects into the test DB (test pollution,
  # not real-vault leak — but it breaks STUCK_ESCALATED dedupe accounting).
  export ARK_PORTFOLIO_ROOT="$TMP/portfolio_isolated_empty"
  mkdir -p "$ARK_HOME/INBOX" "$ARK_HOME/observability" "$ARK_PORTFOLIO_ROOT"
  _continuous_refresh_paths

  # Initialise isolated DB so _policy_log goes there, not real DB.
  if type db_init >/dev/null 2>&1; then
    db_init >/dev/null 2>&1
  fi

  # Mock `ark` on PATH: success unless filename contains "fail" pattern.
  local MOCK_BIN="$TMP/bin"
  mkdir -p "$MOCK_BIN"
  cat > "$MOCK_BIN/ark" <<'MOCK_ARK'
#!/usr/bin/env bash
# Mock ark: success unless ARK_MOCK_FAIL=1 is set.
if [[ "${ARK_MOCK_FAIL:-0}" == "1" ]]; then
  echo "mock-ark: forced failure (ARK_MOCK_FAIL=1)" >&2
  exit 1
fi
echo "mock-ark invoked: $*"
exit 0
MOCK_ARK
  chmod +x "$MOCK_BIN/ark"
  export PATH="$MOCK_BIN:$PATH"

  # Helper: count audit rows for class:continuous matching a decision string.
  _ct_count() {
    local decision="$1"
    if type db_path >/dev/null 2>&1 && [[ -f "$(db_path)" ]]; then
      sqlite3 "$(db_path)" "SELECT COUNT(*) FROM decisions WHERE class='continuous' AND decision='$decision';" 2>/dev/null
    else
      echo 0
    fi
  }

  # ----------------------------------------------------------------------
  # Test 1: Empty INBOX → tick returns 0; TICK_START + TICK_COMPLETE only.
  # ----------------------------------------------------------------------
  echo "Test 1: Empty INBOX tick"
  continuous_tick >/dev/null 2>&1
  local rc=$?
  _ct_assert_eq "0" "$rc" "Test 1: empty-INBOX tick returns 0"
  _ct_assert_eq "1" "$(_ct_count TICK_START)" "Test 1a: TICK_START logged once"
  _ct_assert_eq "1" "$(_ct_count TICK_COMPLETE)" "Test 1b: TICK_COMPLETE logged once"
  _ct_assert_eq "0" "$(_ct_count INBOX_DISPATCH)" "Test 1c: no INBOX_DISPATCH on empty"
  _ct_assert_eq "0" "$(_ct_count INBOX_PROCESSED)" "Test 1d: no INBOX_PROCESSED on empty"

  # ----------------------------------------------------------------------
  # Test 2: One valid resume file → dispatched; file moves to processed/<date>/
  # ----------------------------------------------------------------------
  echo ""
  echo "Test 2: Valid resume file"
  cat > "$INBOX_DIR/02-resume.md" <<'EOF'
---
intent: resume
customer: acme
---
# resume project
EOF
  continuous_tick >/dev/null 2>&1
  local today
  today=$(date -u +%Y-%m-%d)
  if [[ -f "$INBOX_DIR/processed/$today/02-resume.md" ]]; then
    _ct_assert_eq "1" "1" "Test 2: file moved to processed/$today/"
  else
    _ct_assert_eq "1" "0" "Test 2: file moved to processed/$today/"
  fi
  _ct_assert_eq "1" "$(_ct_count INBOX_PROCESSED)" "Test 2a: INBOX_PROCESSED row logged"
  _ct_assert_eq "1" "$(_ct_count INBOX_DISPATCH)" "Test 2b: INBOX_DISPATCH row logged"

  # ----------------------------------------------------------------------
  # Test 3: Malformed file → renamed .malformed + INBOX_MALFORMED logged
  # ----------------------------------------------------------------------
  echo ""
  echo "Test 3: Malformed file"
  cat > "$INBOX_DIR/03-bad.md" <<'EOF'
no frontmatter at all
just garbage
EOF
  continuous_tick >/dev/null 2>&1
  if [[ -f "$INBOX_DIR/03-bad.malformed" ]]; then
    _ct_assert_eq "1" "1" "Test 3: file renamed .malformed"
  else
    _ct_assert_eq "1" "0" "Test 3: file renamed .malformed (got: $(ls "$INBOX_DIR" | tr '\n' ' '))"
  fi
  _ct_assert_eq "1" "$(_ct_count INBOX_MALFORMED)" "Test 3a: INBOX_MALFORMED row logged"

  # ----------------------------------------------------------------------
  # Test 4: Failing intent → renamed .failed + ESCALATIONS entry queued
  # ----------------------------------------------------------------------
  echo ""
  echo "Test 4: Failing dispatch"
  cat > "$INBOX_DIR/04-fail.md" <<'EOF'
---
intent: resume
customer: failcorp
---
# this will fail
EOF
  ARK_MOCK_FAIL=1 continuous_tick >/dev/null 2>&1
  if [[ -f "$INBOX_DIR/04-fail.failed" ]]; then
    _ct_assert_eq "1" "1" "Test 4: file renamed .failed"
  else
    _ct_assert_eq "1" "0" "Test 4: file renamed .failed (got: $(ls "$INBOX_DIR" | tr '\n' ' '))"
  fi
  _ct_assert_eq "1" "$(_ct_count INBOX_FAILED)" "Test 4a: INBOX_FAILED row logged"
  if [[ -f "$ARK_HOME/ESCALATIONS.md" ]]; then
    _ct_assert_eq "1" "1" "Test 4b: ESCALATIONS.md created (escalation queued)"
  else
    _ct_assert_eq "1" "0" "Test 4b: ESCALATIONS.md created"
  fi

  # ----------------------------------------------------------------------
  # Test 5: PAUSE file present → tick exits 0; PAUSE_ACTIVE row; no new processing
  # ----------------------------------------------------------------------
  echo ""
  echo "Test 5: PAUSE file"
  : > "$PAUSE_FILE"
  cat > "$INBOX_DIR/05-paused.md" <<'EOF'
---
intent: resume
---
# would-be processed
EOF
  local before_pause_count
  before_pause_count=$(_ct_count INBOX_PROCESSED)
  continuous_tick >/dev/null 2>&1
  rc=$?
  _ct_assert_eq "0" "$rc" "Test 5: paused tick returns 0"
  _ct_assert_eq "1" "$(_ct_count PAUSE_ACTIVE)" "Test 5a: PAUSE_ACTIVE row logged"
  if [[ -f "$INBOX_DIR/05-paused.md" ]]; then
    _ct_assert_eq "1" "1" "Test 5b: INBOX file untouched while paused"
  else
    _ct_assert_eq "1" "0" "Test 5b: INBOX file untouched while paused"
  fi
  _ct_assert_eq "$before_pause_count" "$(_ct_count INBOX_PROCESSED)" "Test 5c: no new INBOX_PROCESSED while paused"
  rm -f "$PAUSE_FILE"
  rm -f "$INBOX_DIR/05-paused.md"

  # ----------------------------------------------------------------------
  # Test 6: Lock contention → second tick logs LOCK_CONTENDED
  # ----------------------------------------------------------------------
  echo ""
  echo "Test 6: Lock contention"
  mkdir -p "$LOCK_DIR"  # simulate another tick holding lock
  continuous_tick >/dev/null 2>&1
  rc=$?
  _ct_assert_eq "0" "$rc" "Test 6: contended tick returns 0"
  _ct_assert_eq "1" "$(_ct_count LOCK_CONTENDED)" "Test 6a: LOCK_CONTENDED row logged"
  rmdir "$LOCK_DIR" 2>/dev/null || true

  # ----------------------------------------------------------------------
  # Test 7: Daily cap = 0 → DAILY_CAP_HIT, no INBOX scan
  # ----------------------------------------------------------------------
  echo ""
  echo "Test 7: Daily cap exceeded (cap=0)"
  cat > "$INBOX_DIR/07-capped.md" <<'EOF'
---
intent: resume
---
# would-be processed
EOF
  # Override policy_config_get for cap key only via env, by shadowing the func.
  # Simpler: monkey-patch policy_config_get for this test region.
  _orig_pcg=$(declare -f policy_config_get)
  policy_config_get() {
    if [[ "$1" == "continuous.daily_token_cap" ]]; then
      echo "0"
      return 0
    fi
    echo "$2"
  }
  local before_cap_count
  before_cap_count=$(_ct_count INBOX_PROCESSED)
  continuous_tick >/dev/null 2>&1
  _ct_assert_eq "1" "$(_ct_count DAILY_CAP_HIT)" "Test 7: DAILY_CAP_HIT row logged"
  _ct_assert_eq "$before_cap_count" "$(_ct_count INBOX_PROCESSED)" "Test 7a: no INBOX_PROCESSED while capped"
  # Restore original
  eval "$_orig_pcg"
  rm -f "$INBOX_DIR/07-capped.md"

  # ----------------------------------------------------------------------
  # Test 8: Daily cap not exceeded → returns 0
  # ----------------------------------------------------------------------
  echo ""
  echo "Test 8: Daily cap under threshold"
  if continuous_check_daily_cap 2>/dev/null; then
    _ct_assert_eq "1" "1" "Test 8: continuous_check_daily_cap returns 0 under cap"
  else
    _ct_assert_eq "1" "0" "Test 8: continuous_check_daily_cap returns 0 under cap"
  fi

  # ----------------------------------------------------------------------
  # Test 9: Two files (good + malformed) in one tick — both lifecycled correctly
  # ----------------------------------------------------------------------
  echo ""
  echo "Test 9: Mixed batch (good + malformed)"
  cat > "$INBOX_DIR/09-good.md" <<'EOF'
---
intent: promote-lessons
---
# promote
EOF
  cat > "$INBOX_DIR/09-bad.md" <<'EOF'
not a frontmatter file
EOF
  local before_proc=$(_ct_count INBOX_PROCESSED)
  local before_mal=$(_ct_count INBOX_MALFORMED)
  continuous_tick >/dev/null 2>&1
  local after_proc=$(_ct_count INBOX_PROCESSED)
  local after_mal=$(_ct_count INBOX_MALFORMED)
  _ct_assert_eq "1" "$((after_proc - before_proc))" "Test 9: one new INBOX_PROCESSED"
  _ct_assert_eq "1" "$((after_mal - before_mal))" "Test 9a: one new INBOX_MALFORMED"
  if [[ -f "$INBOX_DIR/09-bad.malformed" ]] && [[ ! -f "$INBOX_DIR/09-good.md" ]]; then
    _ct_assert_eq "1" "1" "Test 9b: good→processed, bad→.malformed"
  else
    _ct_assert_eq "1" "0" "Test 9b: good→processed, bad→.malformed"
  fi

  # ----------------------------------------------------------------------
  # Test 10: Lock dir is removed after every tick (trap discipline)
  # ----------------------------------------------------------------------
  echo ""
  echo "Test 10: Lock cleanup"
  if [[ ! -d "$LOCK_DIR" ]]; then
    _ct_assert_eq "1" "1" "Test 10: lock dir absent after tick (trap released)"
  else
    _ct_assert_eq "1" "0" "Test 10: lock dir absent after tick (trap released)"
  fi

  # ----------------------------------------------------------------------
  # Test 11: 3 consecutive failure ticks → PAUSE auto-created
  # ----------------------------------------------------------------------
  echo ""
  echo "Test 11: 3-fail auto-pause"
  rm -f "$FAIL_COUNT_FILE" "$PAUSE_FILE"
  local i
  for i in 1 2 3; do
    cat > "$INBOX_DIR/fail-$i.md" <<EOF
---
intent: resume
customer: failcorp$i
---
# fail $i
EOF
    ARK_MOCK_FAIL=1 continuous_tick >/dev/null 2>&1
  done
  if [[ -f "$PAUSE_FILE" ]]; then
    _ct_assert_eq "1" "1" "Test 11: PAUSE auto-created after 3 consecutive failures"
  else
    _ct_assert_eq "1" "0" "Test 11: PAUSE auto-created after 3 consecutive failures"
  fi
  local auto_pause_n
  auto_pause_n=$(_ct_count AUTO_PAUSE_3_FAIL)
  if [[ "$auto_pause_n" -ge "1" ]]; then
    _ct_assert_eq "1" "1" "Test 11a: AUTO_PAUSE_3_FAIL row logged"
  else
    _ct_assert_eq "1" "0" "Test 11a: AUTO_PAUSE_3_FAIL row logged (got $auto_pause_n)"
  fi
  rm -f "$PAUSE_FILE" "$FAIL_COUNT_FILE"
  rm -f "$INBOX_DIR/"fail-*.failed 2>/dev/null

  # ----------------------------------------------------------------------
  # Test 12: Successful tick clears fail counter
  # ----------------------------------------------------------------------
  echo ""
  echo "Test 12: Success resets fail counter"
  echo "2" > "$FAIL_COUNT_FILE"
  cat > "$INBOX_DIR/12-good.md" <<'EOF'
---
intent: resume
---
# good
EOF
  continuous_tick >/dev/null 2>&1
  if [[ ! -f "$FAIL_COUNT_FILE" ]]; then
    _ct_assert_eq "1" "1" "Test 12: fail counter cleared after success"
  else
    _ct_assert_eq "1" "0" "Test 12: fail counter cleared after success (still: $(cat "$FAIL_COUNT_FILE"))"
  fi

  # ----------------------------------------------------------------------
  # Test 13: Sentinel sections present
  # ----------------------------------------------------------------------
  echo ""
  echo "Test 13: Sentinel sections for 07-03 + 07-04"
  local self_path="${BASH_SOURCE[0]}"
  if grep -q '# === SECTION: health-monitor (Plan 07-03) ===' "$self_path"; then
    _ct_assert_eq "1" "1" "Test 13: health-monitor sentinel present"
  else
    _ct_assert_eq "1" "0" "Test 13: health-monitor sentinel present"
  fi
  if grep -q '# === SECTION: subcommands (Plan 07-04) ===' "$self_path"; then
    _ct_assert_eq "1" "1" "Test 13a: subcommands sentinel present"
  else
    _ct_assert_eq "1" "0" "Test 13a: subcommands sentinel present"
  fi

  # ----------------------------------------------------------------------
  # Test 14: No `read -p` invocation in code (regression guard)
  # ----------------------------------------------------------------------
  echo ""
  echo "Test 14: Hygiene checks"
  if grep -nE '^[[:space:]]*read[[:space:]]+-p' "$self_path" >/dev/null 2>&1; then
    _ct_assert_eq "1" "0" "Test 14: no read -p in code"
  else
    _ct_assert_eq "1" "1" "Test 14: no read -p in code"
  fi
  if grep -nE '(^[[:space:]]*declare[[:space:]]+-A[[:space:]])|(^[[:space:]]*mapfile[[:space:]])' "$self_path" >/dev/null 2>&1; then
    _ct_assert_eq "1" "0" "Test 14a: bash 3 compat (no declare -A/mapfile)"
  else
    _ct_assert_eq "1" "1" "Test 14a: bash 3 compat (no declare -A/mapfile)"
  fi

  # ----------------------------------------------------------------------
  # Test 15: Real-vault md5 invariant — real policy.db unchanged
  # ----------------------------------------------------------------------
  echo ""
  echo "Test 15: Real-vault md5 invariant"
  if [[ -n "$REAL_DB_MD5_BEFORE" ]]; then
    REAL_DB_MD5_AFTER=$(md5 -q "$real_db" 2>/dev/null || md5sum "$real_db" 2>/dev/null | awk '{print $1}')
    _ct_assert_eq "$REAL_DB_MD5_BEFORE" "$REAL_DB_MD5_AFTER" "Test 15: real ~/vaults/ark/observability/policy.db md5 unchanged"
  else
    echo "  ⏭  Test 15: skipped (no real policy.db on this system)"
    pass=$((pass+1))
  fi

  # ----------------------------------------------------------------------
  # Test 16-21: Health-monitor (Plan 07-03)
  # Synthetic portfolio under $TMP/portfolio with mktemp isolation.
  # Real ~/code projects MUST NOT be flagged (ARK_PORTFOLIO_ROOT override).
  # ----------------------------------------------------------------------
  echo ""
  echo "Test 16: Health-monitor — fresh project (not stuck)"
  local TMP_PORT="$TMP/portfolio"
  mkdir -p "$TMP_PORT"
  export ARK_PORTFOLIO_ROOT="$TMP_PORT"

  # Helper: create a synthetic project. $1=slug $2=mtime_age_seconds $3=git_age_or_none
  _ct_make_proj() {
    local s="$1" mtime_age="$2" git_mode="$3"
    local p="$TMP_PORT/$s"
    mkdir -p "$p/.planning"
    cat > "$p/.planning/STATE.md" <<EOF
---
gsd_state_version: 1.0
current_phase: "Phase 7 (synthetic-${s})"
status: in-progress
---
# synthetic
EOF
    if [[ "$mtime_age" != "0" ]]; then
      # touch -t YYYYMMDDHHMM (no seconds; close enough for >24h boundary)
      local epoch=$(( $(date +%s) - mtime_age ))
      local stamp
      stamp=$(date -r "$epoch" +%Y%m%d%H%M 2>/dev/null)
      [[ -n "$stamp" ]] && touch -t "$stamp" "$p/.planning/STATE.md"
    fi
    if [[ "$git_mode" == "fresh" ]]; then
      ( cd "$p" && git init -q 2>/dev/null && git config user.email t@t && git config user.name t \
        && git commit -q --allow-empty -m "init" 2>/dev/null )
    elif [[ "$git_mode" == "stale" ]]; then
      # Backdated commit (48h ago) via GIT_*_DATE env on initial commit.
      local back_epoch=$(( $(date +%s) - 172800 ))
      ( cd "$p" && git init -q 2>/dev/null && git config user.email t@t && git config user.name t \
        && GIT_AUTHOR_DATE="$back_epoch -0000" GIT_COMMITTER_DATE="$back_epoch -0000" \
           git commit -q --allow-empty -m "init" 2>/dev/null )
    fi
    # git_mode=="none" → no git repo at all, last_commit_epoch empty → stuck_git=1
    echo "$p"
  }

  # Test 16: fresh STATE.md → not stuck (no STUCK row added)
  local fresh_proj
  fresh_proj=$(_ct_make_proj "fresh-proj" "0" "fresh")
  local stuck_before=$(_ct_count STUCK_PHASE_DETECTED)
  continuous_health_monitor >/dev/null 2>&1
  local stuck_after=$(_ct_count STUCK_PHASE_DETECTED)
  _ct_assert_eq "$stuck_before" "$stuck_after" "Test 16: fresh project not flagged"

  # Test 17: stuck STATE.md (>24h) + no recent commits → STUCK_PHASE_DETECTED logged
  echo ""
  echo "Test 17: Stuck project flagged"
  rm -rf "$TMP_PORT"/* 2>/dev/null
  local stuck_proj
  stuck_proj=$(_ct_make_proj "stuck-proj" "90000" "none")
  stuck_before=$(_ct_count STUCK_PHASE_DETECTED)
  continuous_health_monitor >/dev/null 2>&1
  stuck_after=$(_ct_count STUCK_PHASE_DETECTED)
  _ct_assert_eq "1" "$((stuck_after - stuck_before))" "Test 17: STUCK_PHASE_DETECTED row added once"

  # Verify reason encodes slug:phase group key (correlation_id is FK-constrained
  # to decision_id chain, so stuck-group key lives in reason as 'stuck:<slug>:<phase>').
  local corr_check
  if [[ -n "$(db_path 2>/dev/null)" ]] && [[ -f "$(db_path)" ]]; then
    corr_check=$(sqlite3 "$(db_path)" \
      "SELECT reason FROM decisions WHERE class='continuous' AND decision='STUCK_PHASE_DETECTED' AND reason LIKE 'stuck:stuck-proj:%' ORDER BY ts DESC LIMIT 1;" \
      2>/dev/null)
  fi
  if [[ "$corr_check" == stuck:stuck-proj:Phase\ 7\ \(synthetic-stuck-proj\)\ age:* ]]; then
    _ct_assert_eq "1" "1" "Test 17a: reason carries stuck:slug:phase group key"
  else
    _ct_assert_eq "1" "0" "Test 17a: reason group key (got: '$corr_check')"
  fi

  # Test 18: 3 invocations within 60min → 3 STUCK rows + 1 STUCK_ESCALATED + ESCALATIONS entry
  echo ""
  echo "Test 18: 3 ticks → escalation"
  # Already 1 STUCK row from Test 17. Run 2 more.
  continuous_health_monitor >/dev/null 2>&1
  continuous_health_monitor >/dev/null 2>&1
  local total_stuck=$(_ct_count STUCK_PHASE_DETECTED)
  if [[ "$total_stuck" -ge 3 ]]; then
    _ct_assert_eq "1" "1" "Test 18: ≥3 STUCK_PHASE_DETECTED rows accumulated"
  else
    _ct_assert_eq "1" "0" "Test 18: ≥3 STUCK_PHASE_DETECTED rows (got $total_stuck)"
  fi
  local escalated_n=$(_ct_count STUCK_ESCALATED)
  _ct_assert_eq "1" "$escalated_n" "Test 18a: exactly 1 STUCK_ESCALATED row"
  if [[ -f "$ARK_HOME/ESCALATIONS.md" ]] && grep -q "stuck-proj" "$ARK_HOME/ESCALATIONS.md" 2>/dev/null; then
    _ct_assert_eq "1" "1" "Test 18b: ESCALATIONS.md mentions stuck-proj"
  else
    _ct_assert_eq "1" "0" "Test 18b: ESCALATIONS.md mentions stuck-proj"
  fi

  # Test 19: 4th invocation within same window → no new STUCK_ESCALATED (24h dedupe)
  echo ""
  echo "Test 19: 24h dedupe"
  continuous_health_monitor >/dev/null 2>&1
  local escalated_n2=$(_ct_count STUCK_ESCALATED)
  _ct_assert_eq "$escalated_n" "$escalated_n2" "Test 19: re-running does not re-escalate (24h dedupe)"

  # Test 20: continuous_auto_pause_check — 3 last TICK_COMPLETE all clean → no PAUSE
  echo ""
  echo "Test 20: auto-pause-check — clean ticks → no PAUSE"
  rm -f "$PAUSE_FILE"
  # Insert 3 fresh clean TICK_COMPLETE rows so the last-3 window is clean.
  _policy_log "continuous" "TICK_COMPLETE" "p:0 f:0 m:0" "null" >/dev/null 2>&1
  _policy_log "continuous" "TICK_COMPLETE" "p:0 f:0 m:0" "null" >/dev/null 2>&1
  _policy_log "continuous" "TICK_COMPLETE" "p:1 f:0 m:0" "null" >/dev/null 2>&1
  continuous_auto_pause_check
  if [[ ! -f "$PAUSE_FILE" ]]; then
    _ct_assert_eq "1" "1" "Test 20: clean tail → no PAUSE created"
  else
    _ct_assert_eq "1" "0" "Test 20: clean tail → no PAUSE created"
  fi

  # Test 21: 3 consecutive TICK_COMPLETE with f:N>0 → PAUSE + AUTO_PAUSED row + idempotent
  echo ""
  echo "Test 21: auto-pause-check — 3 failure ticks → PAUSE"
  rm -f "$PAUSE_FILE"
  _policy_log "continuous" "TICK_COMPLETE" "p:0 f:1 m:0" "null" >/dev/null 2>&1
  _policy_log "continuous" "TICK_COMPLETE" "p:0 f:2 m:0" "null" >/dev/null 2>&1
  _policy_log "continuous" "TICK_COMPLETE" "p:0 f:1 m:0" "null" >/dev/null 2>&1
  local ap_before=$(_ct_count AUTO_PAUSED)
  continuous_auto_pause_check
  local ap_after=$(_ct_count AUTO_PAUSED)
  if [[ -f "$PAUSE_FILE" ]]; then
    _ct_assert_eq "1" "1" "Test 21: PAUSE created on 3 failure ticks"
  else
    _ct_assert_eq "1" "0" "Test 21: PAUSE created on 3 failure ticks"
  fi
  _ct_assert_eq "1" "$((ap_after - ap_before))" "Test 21a: exactly 1 AUTO_PAUSED row added"
  # Idempotent: re-run with PAUSE present → no new AUTO_PAUSED row
  continuous_auto_pause_check
  local ap_idem=$(_ct_count AUTO_PAUSED)
  _ct_assert_eq "$ap_after" "$ap_idem" "Test 21b: idempotent (PAUSE present → no-op)"
  rm -f "$PAUSE_FILE"

  # Test 22: Sentinel byte boundaries — subcommands section (07-04 area) unchanged.
  # Use first-occurrence-only awk (the test code below references the marker
  # strings in comments, which would otherwise confuse a /pat/,/pat/ range).
  echo ""
  echo "Test 22: Subcommands sentinel section untouched (07-04 area)"
  local sub_md5
  sub_md5=$(awk '
    /^# === SECTION: subcommands \(Plan 07-04\) ===$/ { f=1 }
    f { print }
    /^# === END SECTION: subcommands ===$/ { if (f) { exit } }
  ' "$self_path" | md5 -q 2>/dev/null \
    || awk '
    /^# === SECTION: subcommands \(Plan 07-04\) ===$/ { f=1 }
    f { print }
    /^# === END SECTION: subcommands ===$/ { if (f) { exit } }
  ' "$self_path" | md5sum | awk '{print $1}')
  # Expected baseline captured at Plan 07-03 implementation time
  # (07-02 set the section content; this hash freezes it for downstream waves).
  if [[ "$sub_md5" == "2df5ee72a693c4d81ac7bd760a955ab5" ]]; then
    _ct_assert_eq "1" "1" "Test 22: subcommands sentinel md5 byte-identical to 07-02 baseline"
  else
    _ct_assert_eq "1" "0" "Test 22: subcommands sentinel md5 baseline (got: $sub_md5)"
  fi

  unset ARK_PORTFOLIO_ROOT

  # Cleanup
  rm -rf "$TMP" 2>/dev/null
  unset ARK_HOME ARK_POLICY_DB
  _continuous_refresh_paths

  echo ""
  local total=$((pass+fail))
  echo "RESULT: $pass/$total pass"
  if [[ "$fail" -eq 0 ]]; then
    echo "✅ ALL ARK-CONTINUOUS CORE TESTS PASSED"
    return 0
  else
    echo "❌ $fail/$total tests failed"
    return 1
  fi
}

# === CLI guard — only act when invoked directly ===
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    --self-test|self-test|test)
      continuous_self_test
      exit $?
      ;;
    --tick|tick)
      continuous_tick
      exit $?
      ;;
    "")
      # Default: silent no-op (lib sourceable without side effects)
      :
      ;;
    *)
      echo "Usage: $0 [--self-test|--tick]" >&2
      exit 2
      ;;
  esac
fi
