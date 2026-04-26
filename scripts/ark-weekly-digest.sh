#!/usr/bin/env bash
# ark-weekly-digest.sh — Phase 7 Plan 07-06 (AOS Continuous Operation)
#
# Standalone weekly digest aggregator + launchd plist installer.
#
# Aggregates the previous 7 days of policy.db activity into a markdown
# report at ~/vaults/ark/observability/weekly-digest-YYYY-WW.md (ISO week).
# Runs from a separate launchd plist (Sunday 09:00 local) so it doesn't
# compete with the main daemon's StartInterval cadence.
#
# Six sections per CONTEXT.md D-CONT-WEEKLY-DIGEST:
#   1. Projects shipped       (class='dispatcher' decision='ROUTED' outcome=success)
#   2. Phases completed       (distinct project,phase pairs from dispatcher rows)
#   3. Escalations resolved   (class='escalation' decision='RESOLVED')
#   4. Learner promotions     (class='self_improve' + class='lesson_promote' PROMOTED)
#   5. Budget burn            (sum of context.tokens for class='budget')
#   6. Dashboard URL          (static line)
#
# Bash 3 compatible. macOS launchd. Single-writer audit log preserved.
# All SQL via sqlite3 -readonly. Atomic write (.tmp + mv). No `read -p`.
#
# CLI:
#   ark-weekly-digest.sh --generate [--week YYYY-WW]
#   ark-weekly-digest.sh --install
#   ark-weekly-digest.sh --uninstall
#   ark-weekly-digest.sh --self-test

# Sourceable + executable: keep no `set -e` at top level so callers aren't broken.

# === Path resolution (honors ARK_HOME for test isolation) ===
_wd_refresh_paths() {
  VAULT_PATH="${ARK_HOME:-$HOME/vaults/ark}"
  OBSERVABILITY="$VAULT_PATH/observability"
  POLICY_DB="${ARK_POLICY_DB:-$OBSERVABILITY/policy.db}"
}
_wd_refresh_paths

# === Source ark-policy.sh for _policy_log + db_init ===
_WD_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
# shellcheck disable=SC1091
if [[ -f "$_WD_SCRIPT_DIR/ark-policy.sh" ]]; then
  source "$_WD_SCRIPT_DIR/ark-policy.sh" >/dev/null 2>&1
fi

# === SQL helpers (read-only) ===
_wd_sql_ro() {
  # $1 = SQL; emits result on stdout; safe on missing db
  if [[ ! -f "$POLICY_DB" ]]; then
    echo ""
    return 0
  fi
  sqlite3 -readonly "$POLICY_DB" "$1" 2>/dev/null
}

# === Section query functions ===

# Section 1: Projects shipped — distinct projects with ROUTED success in window
_wd_section_shipped() {
  local since="$1"
  _wd_sql_ro "SELECT DISTINCT json_extract(context,'\$.project') FROM decisions WHERE class='dispatcher' AND decision='ROUTED' AND outcome='success' AND ts >= '$since' AND json_extract(context,'\$.project') IS NOT NULL ORDER BY 1;"
}

# Section 2: Phases completed — (project, phase) pairs with counts
_wd_section_phases() {
  local since="$1"
  _wd_sql_ro "SELECT json_extract(context,'\$.project') AS p, json_extract(context,'\$.phase') AS ph, COUNT(*) FROM decisions WHERE class='dispatcher' AND decision='ROUTED' AND ts >= '$since' AND json_extract(context,'\$.project') IS NOT NULL GROUP BY p, ph ORDER BY p, ph;"
}

# Section 3: Escalations — counts queued + resolved
_wd_section_escalations_resolved() {
  local since="$1"
  _wd_sql_ro "SELECT COUNT(*) FROM decisions WHERE class='escalation' AND decision='RESOLVED' AND ts >= '$since';"
}

_wd_section_escalations_queued() {
  local since="$1"
  _wd_sql_ro "SELECT COUNT(*) FROM decisions WHERE class='escalation' AND decision NOT IN ('RESOLVED') AND ts >= '$since';"
}

# Section 4: Learner promotions — both self_improve + lesson_promote PROMOTED
_wd_section_promotions() {
  local since="$1"
  _wd_sql_ro "SELECT class, decision_id, IFNULL(reason,'') FROM decisions WHERE class IN ('self_improve','lesson_promote') AND decision='PROMOTED' AND ts >= '$since' ORDER BY ts;"
}

# Section 5: Budget burn — sum of context.tokens
_wd_section_budget_burn() {
  local since="$1"
  local v
  v=$(_wd_sql_ro "SELECT COALESCE(SUM(CAST(json_extract(context,'\$.tokens') AS INTEGER)),0) FROM decisions WHERE class IN ('budget','dispatch','dispatcher') AND ts >= '$since';")
  echo "${v:-0}"
}

# Per-customer breakdown for budget burn
_wd_section_budget_per_customer() {
  local since="$1"
  _wd_sql_ro "SELECT IFNULL(json_extract(context,'\$.customer'),'(none)') AS cust, COALESCE(SUM(CAST(json_extract(context,'\$.tokens') AS INTEGER)),0) FROM decisions WHERE class IN ('budget','dispatch','dispatcher') AND ts >= '$since' GROUP BY cust ORDER BY 2 DESC;"
}

# === Main generator ===
weekly_digest_generate() {
  _wd_refresh_paths

  local week=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --week) week="$2"; shift 2;;
      *) shift;;
    esac
  done

  # Determine ISO week (YYYY-WW). Test override via ARK_DIGEST_WEEK.
  if [[ -z "$week" ]]; then
    week="${ARK_DIGEST_WEEK:-$(date +%G-%V)}"
  fi

  # Compute since_iso = 7 days ago (BSD date -v). Test override via
  # ARK_DIGEST_WEEK_START_TS for deterministic seeding.
  local since_iso
  if [[ -n "${ARK_DIGEST_WEEK_START_TS:-}" ]]; then
    since_iso="$ARK_DIGEST_WEEK_START_TS"
  else
    since_iso="$(date -v -7d +%FT%T 2>/dev/null || date +%FT%T)"
  fi

  mkdir -p "$OBSERVABILITY" 2>/dev/null

  local out="$OBSERVABILITY/weekly-digest-$week.md"
  local tmp
  tmp="$(mktemp "$OBSERVABILITY/.weekly-digest-$week.XXXXXX.tmp")" || {
    echo "ERROR: mktemp failed" >&2
    return 1
  }

  # Trap to clean tmp file on interrupt
  # shellcheck disable=SC2064
  trap "rm -f '$tmp'" EXIT INT TERM

  # === Build markdown ===
  {
    echo "# Ark Weekly Digest — Week $week"
    echo
    echo "_Window: since \`$since_iso\` (UTC); generated $(date -u +%Y-%m-%dT%H:%M:%SZ)_"
    echo
    echo "_Run \`ark dashboard\` (or \`ark dashboard --web\`) for live view._"
    echo

    # --- Section 1: Projects shipped ---
    echo "## 1. Projects shipped"
    echo
    local shipped
    shipped="$(_wd_section_shipped "$since_iso")"
    if [[ -z "$shipped" ]]; then
      echo "_No projects shipped this week._"
    else
      echo "| Project |"
      echo "|---------|"
      printf '%s\n' "$shipped" | while IFS= read -r p; do
        [[ -z "$p" ]] && continue
        echo "| $p |"
      done
    fi
    echo

    # --- Section 2: Phases completed ---
    echo "## 2. Phases completed"
    echo
    local phases
    phases="$(_wd_section_phases "$since_iso")"
    if [[ -z "$phases" ]]; then
      echo "_No phases completed this week._"
    else
      echo "| Project | Phase | Dispatches |"
      echo "|---------|-------|------------|"
      printf '%s\n' "$phases" | while IFS='|' read -r p ph c; do
        [[ -z "$p" ]] && continue
        echo "| $p | ${ph:-?} | ${c:-0} |"
      done
    fi
    echo

    # --- Section 3: Escalations ---
    echo "## 3. Escalations resolved + queued"
    echo
    local resolved queued
    resolved="$(_wd_section_escalations_resolved "$since_iso")"
    queued="$(_wd_section_escalations_queued "$since_iso")"
    echo "- Resolved: ${resolved:-0}"
    echo "- Queued (open): ${queued:-0}"
    echo

    # --- Section 4: Learner promotions ---
    echo "## 4. Learner promotions"
    echo
    local proms
    proms="$(_wd_section_promotions "$since_iso")"
    if [[ -z "$proms" ]]; then
      echo "_No promotions this week (universal-patterns + anti-patterns)._"
    else
      echo "| Class | Decision ID | Reason |"
      echo "|-------|-------------|--------|"
      printf '%s\n' "$proms" | while IFS='|' read -r cls did reason; do
        [[ -z "$cls" ]] && continue
        echo "| $cls | $did | ${reason:-} |"
      done
    fi
    echo

    # --- Section 5: Budget burn ---
    echo "## 5. Budget burn"
    echo
    local total
    total="$(_wd_section_budget_burn "$since_iso")"
    echo "- Total tokens burned this week: **${total:-0}**"
    echo
    local per_cust
    per_cust="$(_wd_section_budget_per_customer "$since_iso")"
    if [[ -n "$per_cust" ]]; then
      echo "| Customer | Tokens |"
      echo "|----------|--------|"
      printf '%s\n' "$per_cust" | while IFS='|' read -r cust toks; do
        [[ -z "$cust" ]] && continue
        echo "| $cust | ${toks:-0} |"
      done
    fi
    echo

    # --- Section 6: Tier health (last verify report's pass/fail per tier) ---
    echo "## 6. Tier health"
    echo
    # Mine ark-verify rows from policy.db if any; else dashboard hint
    local tiers
    tiers="$(_wd_sql_ro "SELECT json_extract(context,'\$.tier'), decision, COUNT(*) FROM decisions WHERE class='verify' AND ts >= '$since_iso' GROUP BY 1,2 ORDER BY 1;")"
    if [[ -z "$tiers" ]]; then
      echo "_No verify rows in window. Run \`ark verify\` for current tier status._"
    else
      echo "| Tier | Result | Count |"
      echo "|------|--------|-------|"
      printf '%s\n' "$tiers" | while IFS='|' read -r tier result c; do
        [[ -z "$tier" ]] && continue
        echo "| $tier | $result | $c |"
      done
    fi
    echo

    # --- Footer ---
    echo "---"
    echo
    echo "_Generated by \`scripts/ark-weekly-digest.sh\` · ARK_HOME=\`$VAULT_PATH\`_"
    echo "_Re-run: \`bash scripts/ark-weekly-digest.sh --generate\`_"
  } > "$tmp"

  # Atomic move (same FS — both under $VAULT_PATH/observability)
  mv "$tmp" "$out" || {
    rm -f "$tmp"
    trap - EXIT INT TERM
    return 1
  }
  trap - EXIT INT TERM

  # Audit log (single-writer)
  local ctx
  ctx="{\"file\":\"$(basename "$out")\",\"week\":\"$week\",\"since\":\"$since_iso\"}"
  if command -v _policy_log >/dev/null 2>&1; then
    _policy_log "continuous" "WEEKLY_DIGEST_WRITTEN" "week:$week" "$ctx" >/dev/null 2>&1 || true
  fi

  echo "$out"
  return 0
}

# === Plist install / uninstall ===
weekly_digest_install() {
  local dir="${ARK_LAUNCHAGENTS_DIR:-$HOME/Library/LaunchAgents}"
  mkdir -p "$dir" 2>/dev/null
  local out="$dir/com.ark.weekly-digest.plist"
  local tmp
  tmp="$(mktemp "$dir/.com.ark.weekly-digest.XXXXXX.tmp")" || {
    echo "ERROR: mktemp failed" >&2
    return 1
  }
  # shellcheck disable=SC2064
  trap "rm -f '$tmp'" EXIT INT TERM

  local script_path="$_WD_SCRIPT_DIR/ark-weekly-digest.sh"
  local log_dir="${ARK_HOME:-$HOME/vaults/ark}/observability"

  cat > "$tmp" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.ark.weekly-digest</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$script_path</string>
    <string>--generate</string>
  </array>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Weekday</key>
    <integer>0</integer>
    <key>Hour</key>
    <integer>9</integer>
    <key>Minute</key>
    <integer>0</integer>
  </dict>
  <key>StandardOutPath</key>
  <string>$log_dir/weekly-digest.log</string>
  <key>StandardErrorPath</key>
  <string>$log_dir/weekly-digest.err</string>
  <key>RunAtLoad</key>
  <false/>
</dict>
</plist>
PLIST

  mv "$tmp" "$out" || {
    rm -f "$tmp"
    trap - EXIT INT TERM
    return 1
  }
  trap - EXIT INT TERM

  # Best-effort launchctl load (only if not in test mode)
  if [[ -z "${ARK_LAUNCHAGENTS_DIR:-}" ]] && command -v launchctl >/dev/null 2>&1; then
    launchctl unload "$out" >/dev/null 2>&1 || true
    launchctl load "$out" >/dev/null 2>&1 || \
      echo "⚠️  launchctl load failed (non-fatal). Run manually: launchctl load $out" >&2
  fi

  echo "$out"
  return 0
}

weekly_digest_uninstall() {
  local dir="${ARK_LAUNCHAGENTS_DIR:-$HOME/Library/LaunchAgents}"
  local out="$dir/com.ark.weekly-digest.plist"
  if [[ -z "${ARK_LAUNCHAGENTS_DIR:-}" ]] && command -v launchctl >/dev/null 2>&1; then
    launchctl unload "$out" >/dev/null 2>&1 || true
  fi
  rm -f "$out"
  return 0
}

# === Self-test ===
weekly_digest_self_test() {
  local pass=0
  local fail=0
  local fails=""

  local _real_db_md5_before=""
  if [[ -f "$HOME/vaults/ark/observability/policy.db" ]]; then
    _real_db_md5_before="$(md5 -q "$HOME/vaults/ark/observability/policy.db" 2>/dev/null || md5sum "$HOME/vaults/ark/observability/policy.db" 2>/dev/null | awk '{print $1}')"
  fi

  local tmpdir
  tmpdir="$(mktemp -d -t ark-weekly-digest-test.XXXXXX)" || {
    echo "ERROR: mktemp -d failed" >&2
    return 1
  }
  # Isolate ARK_HOME + LaunchAgents dir + policy db
  export ARK_HOME="$tmpdir/vault"
  export ARK_POLICY_DB="$ARK_HOME/observability/policy.db"
  export ARK_LAUNCHAGENTS_DIR="$tmpdir/launchagents"
  mkdir -p "$ARK_HOME/observability" "$ARK_LAUNCHAGENTS_DIR"

  # Refresh paths inside the script under the new env
  _wd_refresh_paths

  # Init isolated DB via policy-db
  if command -v db_init >/dev/null 2>&1; then
    db_init >/dev/null 2>&1
  else
    sqlite3 "$ARK_POLICY_DB" "CREATE TABLE IF NOT EXISTS decisions (decision_id TEXT PRIMARY KEY, ts TEXT, schema_version INTEGER DEFAULT 1, class TEXT, decision TEXT, reason TEXT, context TEXT, outcome TEXT, correlation_id TEXT);"
  fi

  # Seed: rows within last 7 days (use datetime('now','-3 days'))
  local seed_ts
  seed_ts="$(sqlite3 "$ARK_POLICY_DB" "SELECT datetime('now','-3 days');")"
  sqlite3 "$ARK_POLICY_DB" <<SEED
INSERT INTO decisions (decision_id, ts, class, decision, reason, context, outcome) VALUES
  ('seed-1','$seed_ts','dispatcher','ROUTED','test','{"project":"projA","phase":"01","customer":"acme"}','success'),
  ('seed-2','$seed_ts','dispatcher','ROUTED','test','{"project":"projA","phase":"02","customer":"acme"}','success'),
  ('seed-3','$seed_ts','dispatcher','ROUTED','test','{"project":"projB","phase":"01","customer":"beta"}','success'),
  ('seed-4','$seed_ts','escalation','RESOLVED','test',NULL,NULL),
  ('seed-5','$seed_ts','escalation','QUEUED','test',NULL,NULL),
  ('seed-6','$seed_ts','self_improve','PROMOTED','pattern X promoted',NULL,NULL),
  ('seed-7','$seed_ts','lesson_promote','PROMOTED','lesson Y promoted',NULL,NULL),
  ('seed-8','$seed_ts','budget','PROCEED','test','{"tokens":1500,"customer":"acme"}',NULL),
  ('seed-9','$seed_ts','budget','PROCEED','test','{"tokens":2500,"customer":"beta"}',NULL),
  ('seed-10','$seed_ts','dispatch','PROCEED','test','{"tokens":1000,"customer":"acme"}',NULL);
SEED

  # Force a deterministic week label so re-run idempotency is testable
  export ARK_DIGEST_WEEK="2026-T1"
  export ARK_DIGEST_WEEK_START_TS="$(sqlite3 "$ARK_POLICY_DB" "SELECT datetime('now','-7 days');")"

  # --- Test 1: --generate writes file with expected pattern ---
  local out
  out="$(weekly_digest_generate 2>/dev/null)"
  if [[ -f "$out" && "$out" == *"weekly-digest-2026-T1.md" ]]; then
    pass=$((pass+1))
  else
    fail=$((fail+1)); fails="$fails\n  Test 1: digest file not at expected path: $out"
  fi

  # --- Test 2: 6 section headers present ---
  local section_count
  section_count="$(grep -c '^## ' "$out" 2>/dev/null || echo 0)"
  if [[ "$section_count" -ge 6 ]]; then
    pass=$((pass+1))
  else
    fail=$((fail+1)); fails="$fails\n  Test 2: section header count $section_count < 6"
  fi

  # --- Test 3: section data populated (Projects shipped includes projA + projB) ---
  if grep -q "projA" "$out" && grep -q "projB" "$out"; then
    pass=$((pass+1))
  else
    fail=$((fail+1)); fails="$fails\n  Test 3: projects shipped section missing projA/projB"
  fi

  # --- Test 4: re-run produces byte-identical content (idempotent) ---
  local md5_a md5_b
  md5_a="$(md5 -q "$out" 2>/dev/null || md5sum "$out" 2>/dev/null | awk '{print $1}')"
  weekly_digest_generate >/dev/null 2>&1
  md5_b="$(md5 -q "$out" 2>/dev/null || md5sum "$out" 2>/dev/null | awk '{print $1}')"
  # ts in header changes per-run, so md5 will differ — instead check that
  # body sections (after the timestamp line) are stable. We test by stripping
  # the generated-at line and re-comparing.
  local body_a body_b
  body_a="$(grep -v '_Window:' "$out" | head -200)"
  weekly_digest_generate >/dev/null 2>&1
  body_b="$(grep -v '_Window:' "$out" | head -200)"
  if [[ "$body_a" == "$body_b" ]]; then
    pass=$((pass+1))
  else
    fail=$((fail+1)); fails="$fails\n  Test 4: re-run not idempotent (body differs)"
  fi

  # --- Test 5: WEEKLY_DIGEST_WRITTEN audit row added ---
  local audit_count
  audit_count="$(sqlite3 "$ARK_POLICY_DB" "SELECT COUNT(*) FROM decisions WHERE class='continuous' AND decision='WEEKLY_DIGEST_WRITTEN';")"
  if [[ "${audit_count:-0}" -ge 1 ]]; then
    pass=$((pass+1))
  else
    fail=$((fail+1)); fails="$fails\n  Test 5: WEEKLY_DIGEST_WRITTEN audit row missing (got $audit_count)"
  fi

  # --- Test 6: --install writes plist to ARK_LAUNCHAGENTS_DIR override ---
  local plist
  plist="$(weekly_digest_install 2>/dev/null)"
  if [[ -f "$plist" && "$plist" == "$ARK_LAUNCHAGENTS_DIR/com.ark.weekly-digest.plist" ]]; then
    pass=$((pass+1))
  else
    fail=$((fail+1)); fails="$fails\n  Test 6: plist not written to override dir: $plist"
  fi

  # --- Test 7: plist passes plutil validation ---
  if command -v plutil >/dev/null 2>&1; then
    if plutil -lint "$plist" 2>/dev/null | grep -q "OK"; then
      pass=$((pass+1))
    else
      fail=$((fail+1)); fails="$fails\n  Test 7: plutil -lint failed for $plist"
    fi
  else
    # plutil not available → grep for the required keys instead
    if grep -q "StartCalendarInterval" "$plist" && grep -q "<key>Weekday</key>" "$plist"; then
      pass=$((pass+1))
    else
      fail=$((fail+1)); fails="$fails\n  Test 7: plist missing StartCalendarInterval/Weekday"
    fi
  fi

  # --- Test 8: real ~/vaults/ark/observability/policy.db md5 unchanged ---
  if [[ -n "$_real_db_md5_before" ]]; then
    local _real_db_md5_after
    _real_db_md5_after="$(md5 -q "$HOME/vaults/ark/observability/policy.db" 2>/dev/null || md5sum "$HOME/vaults/ark/observability/policy.db" 2>/dev/null | awk '{print $1}')"
    if [[ "$_real_db_md5_before" == "$_real_db_md5_after" ]]; then
      pass=$((pass+1))
    else
      fail=$((fail+1)); fails="$fails\n  Test 8: real-vault policy.db md5 changed during self-test! before=$_real_db_md5_before after=$_real_db_md5_after"
    fi
  else
    # No real DB — vacuously pass
    pass=$((pass+1))
  fi

  # --- Test 9 (extra): no .tmp leftover after generate ---
  local tmp_leftover
  tmp_leftover="$(find "$ARK_HOME/observability" -name '.weekly-digest-*.tmp' 2>/dev/null | head -1)"
  if [[ -z "$tmp_leftover" ]]; then
    pass=$((pass+1))
  else
    fail=$((fail+1)); fails="$fails\n  Test 9: tmp leftover at $tmp_leftover"
  fi

  # --- Test 10 (extra): plist contains StartCalendarInterval (not StartInterval) ---
  if grep -q "StartCalendarInterval" "$plist" && ! grep -q "<key>StartInterval</key>" "$plist"; then
    pass=$((pass+1))
  else
    fail=$((fail+1)); fails="$fails\n  Test 10: plist must use StartCalendarInterval (not StartInterval)"
  fi

  # --- Test 11 (extra): --uninstall removes plist ---
  weekly_digest_uninstall >/dev/null 2>&1
  if [[ ! -f "$plist" ]]; then
    pass=$((pass+1))
  else
    fail=$((fail+1)); fails="$fails\n  Test 11: --uninstall did not remove plist"
  fi

  # Cleanup
  rm -rf "$tmpdir"
  unset ARK_HOME ARK_POLICY_DB ARK_LAUNCHAGENTS_DIR ARK_DIGEST_WEEK ARK_DIGEST_WEEK_START_TS

  local total=$((pass+fail))
  echo "RESULT: $pass/$total pass"
  if [[ $fail -gt 0 ]]; then
    # shellcheck disable=SC2059
    printf "$fails\n" >&2
    return 1
  fi
  echo "✅ ALL WEEKLY-DIGEST TESTS PASSED"
  return 0
}

# === CLI guard ===
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    --generate) shift; weekly_digest_generate "$@";;
    --install|--install-plist) weekly_digest_install;;
    --uninstall) weekly_digest_uninstall;;
    --self-test) weekly_digest_self_test;;
    -h|--help|"")
      cat <<USAGE
Usage:
  $0 --generate [--week YYYY-WW]   Aggregate last 7 days into weekly-digest-YYYY-WW.md
  $0 --install                     Install ~/Library/LaunchAgents/com.ark.weekly-digest.plist
  $0 --uninstall                   Remove the launchd plist
  $0 --self-test                   Run isolated self-test suite

Env:
  ARK_HOME                         Override vault path (default ~/vaults/ark)
  ARK_LAUNCHAGENTS_DIR             Override LaunchAgents dir (test isolation)
  ARK_DIGEST_WEEK                  Override week label (e.g. 2026-17)
  ARK_DIGEST_WEEK_START_TS         Override since-timestamp for window
USAGE
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Run '$0 --help' for usage." >&2
      exit 2
      ;;
  esac
fi
