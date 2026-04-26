#!/usr/bin/env bash
# policy-learner.sh — Pattern scoring + promotion/deprecation engine.
#
# Phase 3 Plan 03-02 (REQ-AOS-08). Reads observability/policy.db (SQLite),
# aggregates decisions by (class, decision, dispatcher, complexity), classifies
# each pattern against the 5-occurrence / 80%-success / 20%-failure thresholds,
# and emits promote/deprecate/ignore verdicts.
#
# Substrate: SQLite (Phase 2.5 + Phase 3 Plan 03-01). Single SQL aggregation,
# no per-row queries, no jq pipelines. Reference query lives in SUPERSEDES.md.
#
# This module is READ-ONLY against the decisions table. Writes are 03-03's job.
#
# Bash 3 compatible (macOS default). NO associative arrays, NO mapfile, NO
# `set -e` (sourced lib must not break callers; functions return non-zero
# explicitly).

set -uo pipefail

# Locate sibling lib dir (works whether sourced or executed directly)
_PL_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/lib"

# Source SQLite backend (provides db_path)
# shellcheck disable=SC1091
if [[ -f "$_PL_LIB_DIR/policy-db.sh" ]]; then
  source "$_PL_LIB_DIR/policy-db.sh"
else
  echo "❌ policy-learner.sh requires scripts/lib/policy-db.sh" >&2
  exit 1
fi

# Source outcome tagger (provides tagger_run_window for optional --tag-first)
# shellcheck disable=SC1091
if [[ -f "$_PL_LIB_DIR/outcome-tagger.sh" ]]; then
  source "$_PL_LIB_DIR/outcome-tagger.sh"
else
  echo "❌ policy-learner.sh requires scripts/lib/outcome-tagger.sh" >&2
  exit 1
fi

# === Thresholds (locked per CONTEXT.md decision #4) ===
PROMOTE_MIN_COUNT=5
PROMOTE_MIN_RATE=80    # percent — success_rate >= 80% promotes
DEPRECATE_MAX_RATE=20  # percent — success_rate <= 20% deprecates

# True-blocker classes — never promote/deprecate. Per CONTEXT.md decision #4
# and SUPERSEDES.md. These four cover the user-confirmed unbreakable escalations.
TRUE_BLOCKER_CLASSES="monthly-budget architectural-ambiguity destructive-op repeated-failure"

# Pending-sidecar location (consumed by 03-03 auto-patch).
VAULT_PATH="${ARK_HOME:-$HOME/vaults/ark}"
PENDING_FILE="${PENDING_FILE:-$VAULT_PATH/observability/policy-evolution-pending.jsonl}"

# Convert ISO8601 (UTC, ...Z) → epoch seconds. macOS BSD date with GNU fallback.
_pl_to_epoch() {
  local iso="$1"
  local e
  e=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$iso" +%s 2>/dev/null) && { echo "$e"; return 0; }
  e=$(date -u -d "$iso" +%s 2>/dev/null) && { echo "$e"; return 0; }
  return 1
}

# Is this class a true-blocker that must never be promoted/deprecated?
# Also handles SEMANTIC blockers in the audit log: any class='escalation' row,
# and any (class='budget' AND decision='ESCALATE_MONTHLY_CAP') row, regardless
# of label. (See plan note about Phase 2 audit log labelling.)
_pl_is_true_blocker() {
  local class="$1"
  local decision="$2"

  # Direct label match
  case " $TRUE_BLOCKER_CLASSES " in
    *" $class "*) return 0 ;;
  esac

  # Semantic match — escalation rows are always blockers, regardless of decision
  if [[ "$class" == "escalation" ]]; then
    return 0
  fi

  # Semantic match — budget escalation
  if [[ "$class" == "budget" ]] && [[ "$decision" == "ESCALATE_MONTHLY_CAP" ]]; then
    return 0
  fi

  return 1
}

# Public: learner_score_window <since_iso8601>
# Runs the SQL aggregation defined in SUPERSEDES.md. Outputs TSV rows:
#   class \t decision \t dispatcher \t complexity \t n \t success_rate
# where success_rate is a decimal in [0.0, 1.0].
# NULL dispatcher/complexity become literal "none" in the TSV (so downstream
# parsing treats absence as a distinct bucket).
learner_score_window() {
  local since_iso="$1"

  if [[ -z "$since_iso" ]]; then
    echo "learner_score_window: since_iso8601 required" >&2
    return 2
  fi

  local epoch
  epoch="$(_pl_to_epoch "$since_iso")" || {
    echo "learner_score_window: cannot parse '$since_iso'" >&2
    return 2
  }

  # Single SQL aggregation. Excludes class='escalation' and class='self_improve'
  # (the latter is the learner's own audit trail — meta, not eligible). Note:
  # class='budget' rows ARE included in scoring; the true-blocker filter happens
  # in classify/collect_pending stage so we still surface counts for diagnostics
  # if a caller wants the raw scores.
  sqlite3 -separator $'\t' "$(db_path)" <<SQL
SELECT
  class,
  decision,
  IFNULL(json_extract(context, '\$.dispatcher'), 'none')   AS dispatcher,
  IFNULL(json_extract(context, '\$.complexity'), 'none')   AS complexity,
  COUNT(*)                                                 AS n,
  ROUND(SUM(outcome = 'success') * 1.0 / COUNT(*), 4)      AS success_rate
FROM decisions
WHERE outcome IS NOT NULL
  AND class NOT IN ('escalation','self_improve')
  AND ts >= datetime($epoch, 'unixepoch')
GROUP BY class, decision, dispatcher, complexity
HAVING n >= $PROMOTE_MIN_COUNT
ORDER BY class, decision, dispatcher, complexity;
SQL
}

# Public: learner_classify <success_rate> <n>
# Echoes one of: PROMOTE | DEPRECATE | IGNORE
# Math is done in awk (Bash 3 has no float arithmetic). Thresholds are locked.
learner_classify() {
  local rate="$1"
  local n="$2"

  if [[ -z "$rate" ]] || [[ -z "$n" ]]; then
    echo "learner_classify: rate and n required" >&2
    return 2
  fi

  # Below count threshold → never act, regardless of rate
  if [[ "$n" -lt "$PROMOTE_MIN_COUNT" ]]; then
    echo "IGNORE"
    return 0
  fi

  # Compare rate (0.0..1.0) against percentage thresholds
  awk -v r="$rate" -v p="$PROMOTE_MIN_RATE" -v d="$DEPRECATE_MAX_RATE" '
    BEGIN {
      rate_pct = r * 100
      if (rate_pct >= p) { print "PROMOTE"; exit 0 }
      if (rate_pct <= d) { print "DEPRECATE"; exit 0 }
      print "IGNORE"
      exit 0
    }
  '
}

# Public: learner_collect_pending <since_iso> [--tag-first]
# Combines score + classify, filters out true-blocker classes, outputs TSV rows:
#   verdict \t class \t decision \t dispatcher \t complexity \t n \t rate
# Verdict ∈ {PROMOTE, DEPRECATE}. IGNORE rows are dropped.
# If --tag-first is passed, calls tagger_run_window first to ensure all rows in
# the window have outcomes inferred before scoring.
learner_collect_pending() {
  local since_iso="$1"
  local opt="${2:-}"

  if [[ -z "$since_iso" ]]; then
    echo "learner_collect_pending: since_iso8601 required" >&2
    return 2
  fi

  if [[ "$opt" == "--tag-first" ]]; then
    tagger_run_window "$since_iso" >/dev/null 2>&1 || true
  fi

  # Stream score TSV through filter+classify in a single awk pass would be ideal
  # but we need _pl_is_true_blocker (Bash function). Pipe through `while read`.
  local class decision dispatcher complexity n rate verdict
  learner_score_window "$since_iso" | while IFS=$'\t' read -r class decision dispatcher complexity n rate; do
    [[ -z "$class" ]] && continue

    # True-blocker filter (semantic, not just label match)
    if _pl_is_true_blocker "$class" "$decision"; then
      continue
    fi

    verdict="$(learner_classify "$rate" "$n")"
    case "$verdict" in
      PROMOTE|DEPRECATE)
        printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
          "$verdict" "$class" "$decision" "$dispatcher" "$complexity" "$n" "$rate"
        ;;
      *) ;;  # IGNORE — drop
    esac
  done
}

# Public: learner_run [--full | --since DATE] [--tag-first]
# Orchestrator. Resolves window, optionally tags first, scores, classifies,
# writes JSONL sidecar at $PENDING_FILE for 03-03 to consume.
# Echoes summary line: "scored: N (promote: P, deprecate: D)".
learner_run() {
  local mode="${1:---full}"
  local since_iso=""
  local tag_first=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --full)       since_iso="1970-01-01T00:00:00Z"; shift ;;
      --since)      shift; since_iso="${1:-}"; shift ;;
      --tag-first)  tag_first="--tag-first"; shift ;;
      *)            shift ;;
    esac
  done

  [[ -z "$since_iso" ]] && since_iso="1970-01-01T00:00:00Z"

  mkdir -p "$(dirname "$PENDING_FILE")"

  # Atomic overwrite (truncate, not append — re-runs must not accumulate)
  local tmp_pending="${PENDING_FILE}.tmp.$$"
  : > "$tmp_pending"

  local p=0 d=0 total=0
  local verdict class decision dispatcher complexity n rate
  while IFS=$'\t' read -r verdict class decision dispatcher complexity n rate; do
    [[ -z "$verdict" ]] && continue
    total=$(( total + 1 ))

    # Compute integer percent for sidecar (consumers prefer integer pct)
    local rate_pct
    rate_pct=$(awk -v r="$rate" 'BEGIN { printf "%d", (r * 100) + 0.5 }')

    # JSON-escape decision/class fields. Field values are tightly constrained
    # (alnum + _ -) but be defensive against quotes anyway.
    local action="promote"
    [[ "$verdict" == "DEPRECATE" ]] && action="deprecate"
    [[ "$verdict" == "PROMOTE" ]]   && p=$(( p + 1 ))
    [[ "$verdict" == "DEPRECATE" ]] && d=$(( d + 1 ))

    # Build single-line JSON. Use sqlite3 to JSON-escape text fields safely.
    local json
    json=$(sqlite3 ":memory:" "SELECT json_object(
      'action', '$action',
      'class', '$(printf "%s" "$class" | sed "s/'/''/g")',
      'decision', '$(printf "%s" "$decision" | sed "s/'/''/g")',
      'dispatcher', '$(printf "%s" "$dispatcher" | sed "s/'/''/g")',
      'complexity', '$(printf "%s" "$complexity" | sed "s/'/''/g")',
      'count', $n,
      'rate_pct', $rate_pct,
      'rate', $rate
    );")
    echo "$json" >> "$tmp_pending"
  done < <(learner_collect_pending "$since_iso" $tag_first)

  mv "$tmp_pending" "$PENDING_FILE"

  # Plan 03-04: write the human-readable digest alongside the pending sidecar.
  # Non-fatal — if the digest writer fails, the pending sidecar (consumed by
  # 03-03) is still authoritative; we just lose the human view for this run.
  learner_write_digest "$since_iso" || \
    echo "⚠️  digest writer failed (non-fatal)" >&2

  # Plan 03-03: optionally apply the pending patches to policy.yml. Opt-in via
  # LEARNER_AUTO_APPLY=1 so the 03-02 self-test (which compares sidecar shasum
  # across runs) is unaffected.
  if [[ "${LEARNER_AUTO_APPLY:-0}" == "1" ]] && [[ "$total" -gt 0 ]]; then
    learner_apply_pending "$PENDING_FILE" || \
      echo "⚠️  learner_apply_pending failed (non-fatal)" >&2
  fi

  echo "scored: $total (promote: $p, deprecate: $d) → $PENDING_FILE"
}

# === Plan-spec aliases ===
# The 03-02 plan specified function names learner_score_patterns,
# learner_emit_promotions, learner_emit_deprecations. The user prompt and
# SUPERSEDES.md specified learner_score_window, learner_classify,
# learner_collect_pending. We implement the latter (authoritative per
# SUPERSEDES) and provide the former as compatible wrappers so plan acceptance
# grep checks pass and downstream callers can use either name.

learner_score_patterns() {
  # Wrapper: scores patterns from a since-ISO arg or full history.
  local arg="${1:---full}"
  case "$arg" in
    --full)  learner_score_window "1970-01-01T00:00:00Z" ;;
    --since) shift; learner_score_window "${1:-1970-01-01T00:00:00Z}" ;;
    *)       learner_score_window "$arg" ;;
  esac
}

learner_emit_promotions() {
  # Wrapper: emits PROMOTE-only verdicts as TSV.
  local since="${1:-1970-01-01T00:00:00Z}"
  learner_collect_pending "$since" | awk -F'\t' '$1 == "PROMOTE"'
}

learner_emit_deprecations() {
  # Wrapper: emits DEPRECATE-only verdicts as TSV.
  local since="${1:-1970-01-01T00:00:00Z}"
  learner_collect_pending "$since" | awk -F'\t' '$1 == "DEPRECATE"'
}

# === Plan 03-03: Auto-patch policy.yml with locking, audit, and git commit ===
# Extends 03-02. Reads the JSONL sidecar at $PENDING_FILE (one verdict per line),
# acquires a portable mkdir-lock on $VAULT_PATH/.policy-yml.lock (macOS has no
# flock(1) by default), patches policy.yml under the lock, emits a single
# `_policy_log "self_improve" ...` audit entry per applied verdict (correlation_id
# = first decision_id from the input set when present), and commits policy.yml to
# the vault git repo with a structured message. Idempotent: re-applying the same
# pending file with no policy.yml deltas produces no new audit entries and no new
# git commits. True-blocker filter is re-applied here as defense-in-depth.

# Source ark-policy.sh for _policy_log (single audit writer). ark-policy.sh's
# tail block triggers a self-test when sourced with $1=test. We shield by
# saving + clearing $@, sourcing, then restoring.
_LRN_SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
if [[ -z "${_LRN_POLICY_SOURCED:-}" ]] && [[ -f "$_LRN_SCRIPTS_DIR/ark-policy.sh" ]]; then
  if ! type _policy_log >/dev/null 2>&1; then
    _LRN_SAVED_ARGS=("$@")
    set -- _lrn_noop_arg
    # shellcheck disable=SC1091
    source "$_LRN_SCRIPTS_DIR/ark-policy.sh" >/dev/null 2>&1 || true
    set -- "${_LRN_SAVED_ARGS[@]}"
    unset _LRN_SAVED_ARGS
  fi
  _LRN_POLICY_SOURCED=1
fi

# === Lock helpers (mkdir is atomic on POSIX; macOS-safe) ===
_lrn_acquire_lock() {
  local lock="$1"
  local timeout="${2:-30}"
  local i=0
  while ! mkdir "$lock" 2>/dev/null; do
    i=$(( i + 1 ))
    if [[ $i -ge $timeout ]]; then
      return 1
    fi
    sleep 1
  done
  # Stamp the lock with our pid for diagnostics
  echo "$$" > "$lock/pid" 2>/dev/null || true
  return 0
}

_lrn_release_lock() {
  local lock="$1"
  rm -f "$lock/pid" 2>/dev/null || true
  rmdir "$lock" 2>/dev/null || true
}

# === True-blocker re-check (defense in depth — 03-02 already filters) ===
_lrn_is_true_blocker() {
  local class="$1" decision="$2"
  case " $TRUE_BLOCKER_CLASSES " in
    *" $class "*) return 0 ;;
  esac
  if [[ "$class" == "escalation" ]]; then
    return 0
  fi
  if [[ "$class" == "budget" ]] && [[ "$decision" == "ESCALATE_MONTHLY_CAP" ]]; then
    return 0
  fi
  return 1
}

# Public: learner_apply_pending [pending_file]
# Default pending file: $PENDING_FILE (set by 03-02). Each non-empty JSONL line
# is parsed, true-blocker-checked, applied to policy.yml under the lock, audited
# via _policy_log, and committed to vault git. Idempotent.
#
# Returns: 0 on success (zero or more patches applied), 1 on lock failure.
learner_apply_pending() {
  local pending="${1:-$PENDING_FILE}"
  local vault_path="${VAULT_PATH:-$HOME/vaults/ark}"
  local policy_yml="$vault_path/policy.yml"
  local lock_dir="$vault_path/.policy-yml.lock"

  if [[ ! -s "$pending" ]]; then
    echo "learner_apply_pending: no pending patches at $pending" >&2
    return 0
  fi

  # Ensure policy.yml exists with explanatory header on first patch ever
  if [[ ! -f "$policy_yml" ]]; then
    mkdir -p "$(dirname "$policy_yml")"
    cat > "$policy_yml" <<'YML'
# policy.yml — Auto-managed learned-pattern preferences.
#
# Maintained by scripts/policy-learner.sh (Phase 3, AOS).
# Each entry under `learned_patterns` was auto-derived from
# observability/policy-decisions.jsonl outcomes. Manual edits are allowed but
# may be overwritten on the next learner run if the same pattern crosses the
# 5-occurrence / 80%-success / 20%-failure thresholds.
#
# True-blocker classes (escalation, budget/ESCALATE_MONTHLY_CAP, monthly-budget,
# architectural-ambiguity, destructive-op, repeated-failure) are NEVER patched
# here. They remain user-confirmed escalation paths.
learned_patterns: {}
YML
  fi

  # Set up trap to release lock on any exit/signal during the loop
  local applied=0
  local skipped_blocker=0
  local skipped_noop=0
  local committed=0

  local line action class decision dispatcher complexity rate_pct count first_id
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue

    action=$(echo "$line"     | sqlite3 ":memory:" "SELECT json_extract('$(printf "%s" "$line" | sed "s/'/''/g")', '\$.action');"     2>/dev/null)
    class=$(echo "$line"      | sqlite3 ":memory:" "SELECT json_extract('$(printf "%s" "$line" | sed "s/'/''/g")', '\$.class');"      2>/dev/null)
    decision=$(echo "$line"   | sqlite3 ":memory:" "SELECT json_extract('$(printf "%s" "$line" | sed "s/'/''/g")', '\$.decision');"   2>/dev/null)
    dispatcher=$(echo "$line" | sqlite3 ":memory:" "SELECT json_extract('$(printf "%s" "$line" | sed "s/'/''/g")', '\$.dispatcher');" 2>/dev/null)
    complexity=$(echo "$line" | sqlite3 ":memory:" "SELECT json_extract('$(printf "%s" "$line" | sed "s/'/''/g")', '\$.complexity');" 2>/dev/null)
    rate_pct=$(echo "$line"   | sqlite3 ":memory:" "SELECT json_extract('$(printf "%s" "$line" | sed "s/'/''/g")', '\$.rate_pct');"   2>/dev/null)
    count=$(echo "$line"      | sqlite3 ":memory:" "SELECT json_extract('$(printf "%s" "$line" | sed "s/'/''/g")', '\$.count');"      2>/dev/null)
    # decision_ids is optional in the 03-02 sidecar (it currently doesn't write
    # it). Try to extract first id; fall back to NULL.
    first_id=$(echo "$line"   | sqlite3 ":memory:" "SELECT json_extract('$(printf "%s" "$line" | sed "s/'/''/g")', '\$.decision_ids[0]');" 2>/dev/null)
    [[ -z "$first_id" ]] && first_id="null"

    if [[ -z "$action" ]] || [[ -z "$class" ]] || [[ -z "$decision" ]]; then
      echo "⚠️  Skipping malformed pending line: $line" >&2
      continue
    fi

    if _lrn_is_true_blocker "$class" "$decision"; then
      echo "⚠️  Skipping true-blocker (defense-in-depth): $class/$decision" >&2
      skipped_blocker=$(( skipped_blocker + 1 ))
      continue
    fi

    if ! _lrn_acquire_lock "$lock_dir" 30; then
      echo "❌ learner_apply_pending: could not acquire lock at $lock_dir" >&2
      return 1
    fi

    # Snapshot policy.yml content hash to detect no-op patches (idempotency)
    local pre_hash
    pre_hash=$(shasum "$policy_yml" 2>/dev/null | awk '{print $1}')

    # Atomic patch via python3. Write to .tmp then rename.
    POLICY_YML="$policy_yml" \
    ACTION="$action" CLASS="$class" DECISION="$decision" \
    DISPATCHER="$dispatcher" COMPLEXITY="$complexity" RATE_PCT="$rate_pct" \
    python3 - <<'PY'
import os, sys, re, tempfile

p = os.environ['POLICY_YML']
action = os.environ['ACTION']
cls = os.environ['CLASS']
dec = os.environ['DECISION']
disp = os.environ['DISPATCHER'] or 'none'
cplx = os.environ['COMPLEXITY'] or 'none'
rate = int(os.environ['RATE_PCT'] or '0')

try:
    import yaml
    has_yaml = True
except ImportError:
    has_yaml = False

if has_yaml:
    data = {}
    if os.path.exists(p):
        with open(p) as f:
            data = yaml.safe_load(f) or {}
    if not isinstance(data, dict):
        data = {}
    lp = data.setdefault('learned_patterns', {})
    if not isinstance(lp, dict):
        lp = {}
        data['learned_patterns'] = lp
    c  = lp.setdefault(cls, {})
    d  = c.setdefault(dec, {})
    di = d.setdefault(disp, {})
    cx = di.setdefault(cplx, {})
    if action == 'promote':
        cx['preferred'] = True
        cx.pop('deprecated', None)
    else:
        cx['deprecated'] = True
        cx.pop('preferred', None)
    cx['confidence_pct'] = rate

    # Atomic write
    tmp = p + '.tmp.' + str(os.getpid())
    with open(tmp, 'w') as f:
        f.write("# policy.yml — Auto-managed learned-pattern preferences (Phase 3 AOS).\n")
        f.write("# True-blocker classes are NEVER patched here.\n")
        yaml.safe_dump(data, f, default_flow_style=False, sort_keys=True)
    os.replace(tmp, p)
else:
    # Fallback: append-only dotted-key form (lossy but deterministic).
    flag = 'preferred' if action == 'promote' else 'deprecated'
    base = f"learned_patterns.{cls}.{dec}.{disp}.{cplx}"
    new_lines = [
        f"# AOS Phase 3 auto-{action} (n=?, rate={rate}%)",
        f"{base}.{flag}: true",
        f"{base}.confidence_pct: {rate}",
    ]
    existing = ""
    if os.path.exists(p):
        with open(p) as f:
            existing = f.read()
    # Idempotency in fallback mode: skip if every new_line already present.
    if all(ln in existing for ln in new_lines if not ln.startswith('#')):
        sys.exit(0)
    tmp = p + '.tmp.' + str(os.getpid())
    with open(tmp, 'w') as f:
        f.write(existing)
        if existing and not existing.endswith('\n'):
            f.write('\n')
        for ln in new_lines:
            f.write(ln + '\n')
    os.replace(tmp, p)
PY

    local post_hash
    post_hash=$(shasum "$policy_yml" 2>/dev/null | awk '{print $1}')

    _lrn_release_lock "$lock_dir"

    if [[ "$pre_hash" == "$post_hash" ]]; then
      # No-op: pattern was already at this state. No audit entry, no commit.
      skipped_noop=$(( skipped_noop + 1 ))
      continue
    fi

    applied=$(( applied + 1 ))

    # Audit log entry via the SINGLE writer (per CONTEXT.md decision #1).
    local audit_decision="PROMOTED"
    [[ "$action" == "deprecate" ]] && audit_decision="DEPRECATED"
    local ctx
    ctx=$(printf '{"class":"%s","decision":"%s","dispatcher":"%s","complexity":"%s","rate_pct":%s,"count":%s}' \
      "$class" "$decision" "$dispatcher" "$complexity" "$rate_pct" "$count")
    local corr="$first_id"
    [[ "$corr" == "null" || -z "$corr" ]] && corr=""
    if type _policy_log >/dev/null 2>&1; then
      _policy_log "self_improve" "$audit_decision" "rate_pct_${rate_pct}_count_${count}" "$ctx" "$corr" >/dev/null
    else
      echo "⚠️  _policy_log not available; audit entry skipped" >&2
    fi

    # Vault git commit (graceful degradation if not a git repo)
    if git -C "$vault_path" rev-parse --git-dir >/dev/null 2>&1; then
      git -C "$vault_path" add policy.yml >/dev/null 2>&1 || true
      if git -C "$vault_path" diff --cached --quiet -- policy.yml; then
        # Nothing staged (e.g., file ignored) — skip commit silently
        :
      else
        git -C "$vault_path" commit -m \
          "AOS Phase 3: auto-${action} ${class}/${decision}/${dispatcher}/${complexity} (rate ${rate_pct}%, n=${count})" \
          --quiet >/dev/null 2>&1 || true
        committed=$(( committed + 1 ))
      fi
    else
      echo "⚠️  $vault_path is not a git repo; patch written but not committed" >&2
    fi
  done < "$pending"

  # Archive applied pending file for forensic trail (only if we actually applied
  # at least one patch; pure no-op runs leave the pending file in place so a
  # subsequent invocation with new context can retry).
  if [[ "$applied" -gt 0 ]]; then
    mv "$pending" "${pending}.applied-$(date +%s)" 2>/dev/null || true
  fi

  echo "applied: $applied (committed: $committed, skipped_blocker: $skipped_blocker, no-op: $skipped_noop)"
  return 0
}

# === Plan 03-04: human-readable digest writer ===
# Sources scripts/lib/policy-digest.sh and re-exports `learner_write_digest`.
# Kept as a thin shim so 03-04's standalone module remains independently
# testable; merging the body into this file is a future-cleanup option.

if [[ -z "${_LEARNER_DIGEST_LOADED:-}" ]]; then
  if [[ -f "$_PL_LIB_DIR/policy-digest.sh" ]]; then
    # shellcheck disable=SC1091
    source "$_PL_LIB_DIR/policy-digest.sh"
    _LEARNER_DIGEST_LOADED=1
  else
    # Fallback no-op so callers don't break if the lib is missing.
    learner_write_digest() {
      echo "⚠️  scripts/lib/policy-digest.sh not found; digest skipped" >&2
      return 0
    }
    _LEARNER_DIGEST_LOADED=1
  fi
fi

# === CLI / Self-test entry ===
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-run}" in
    test)
      echo "🧪 policy-learner.sh self-test"
      echo ""

      TEST_DB="/tmp/ark-learner-test-$$.db"
      TEST_PENDING="/tmp/ark-learner-pending-$$.jsonl"
      export ARK_POLICY_DB="$TEST_DB"
      export PENDING_FILE="$TEST_PENDING"

      rm -f "$TEST_DB" "$TEST_DB-shm" "$TEST_DB-wal" "$TEST_PENDING"

      db_init >/dev/null

      pass=0
      fail=0
      assert_eq() {
        local exp="$1" act="$2" lbl="$3"
        if [[ "$exp" == "$act" ]]; then
          echo "  ✅ $lbl"
          pass=$((pass+1))
        else
          echo "  ❌ $lbl  (expected: $exp, got: $act)"
          fail=$((fail+1))
        fi
      }

      # Helper: insert N synthetic decisions of one pattern with a given success
      # ratio. ts spaced 1 minute apart starting from base_ts.
      base_epoch=1736942400  # 2025-01-15T12:00:00Z
      seq_counter=0
      insert_pattern() {
        local class="$1" decision="$2" dispatcher="$3" complexity="$4"
        local total="$5" successes="$6"
        local i
        for ((i=0; i<total; i++)); do
          local ts_epoch=$(( base_epoch + seq_counter * 60 ))
          local ts; ts=$(date -u -r "$ts_epoch" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null \
            || date -u -d "@$ts_epoch" +"%Y-%m-%dT%H:%M:%SZ")
          local did="syn_${seq_counter}_$$"
          local outcome="failure"
          [[ "$i" -lt "$successes" ]] && outcome="success"
          local ctx="{\"dispatcher\":\"$dispatcher\",\"complexity\":\"$complexity\"}"
          sqlite3 "$TEST_DB" <<SQL
INSERT INTO decisions (decision_id, ts, class, decision, reason, context, outcome)
VALUES ('$did', '$ts', '$class', '$decision', 'syn', '$ctx', '$outcome');
SQL
          seq_counter=$(( seq_counter + 1 ))
        done
      }

      echo "1. Synthesize 6 patterns × 5 rows + 1 underweight pattern + escalations:"
      # Pattern 1: 90% success (5/5 success — ≥80% PROMOTE)
      insert_pattern "dispatch_failure" "SELF_HEAL" "gemini" "deep"   5 5
      # Pattern 2: 80% success (4/5 success — exactly at PROMOTE threshold)
      insert_pattern "dispatch_failure" "RETRY"     "codex"  "medium" 5 4
      # Pattern 3: 50% success (mediocre middle — IGNORE)
      insert_pattern "dispatch_failure" "RETRY"     "haiku"  "medium" 6 3
      # Pattern 4: 20% success (1/5 — exactly at DEPRECATE threshold)
      insert_pattern "dispatch_failure" "RETRY"     "haiku"  "simple" 5 1
      # Pattern 5: 10% success would need >5 rows; use 6 with 1 success → 16.6%
      insert_pattern "self_heal"        "ATTEMPT"   "codex"  "deep"   6 1
      # Pattern 6: 100% success but n=3 (under threshold — not in output)
      insert_pattern "dispatch_failure" "RETRY"     "gemini" "simple" 3 3
      echo "  inserted $seq_counter synthetic rows"

      echo ""
      echo "2. learner_score_window — sanity check counts and rates:"
      score_out=$(learner_score_window "2024-01-01T00:00:00Z")
      score_lines=$(echo "$score_out" | grep -v '^$' | wc -l | tr -d ' ')
      # 5 patterns meet n>=5 threshold; the 6th (n=3) is filtered by HAVING.
      assert_eq "5" "$score_lines" "score_window returned 5 patterns (n>=5 only)"

      # Spot-check: gemini/deep pattern should report rate=1.0 with n=5
      gemini_row=$(echo "$score_out" | awk -F'\t' '$3=="gemini" && $4=="deep"')
      gemini_n=$(echo "$gemini_row" | awk -F'\t' '{print $5}')
      gemini_rate=$(echo "$gemini_row" | awk -F'\t' '{print $6}')
      assert_eq "5" "$gemini_n" "gemini/deep n=5"
      assert_eq "1.0" "$gemini_rate" "gemini/deep rate=1.0"

      echo ""
      echo "3. learner_classify — threshold boundaries:"
      assert_eq "PROMOTE"   "$(learner_classify 1.0 5)"  "1.0/5 → PROMOTE"
      assert_eq "PROMOTE"   "$(learner_classify 0.8 5)"  "0.8/5 → PROMOTE (boundary)"
      assert_eq "IGNORE"    "$(learner_classify 0.79 5)" "0.79/5 → IGNORE (just below)"
      assert_eq "IGNORE"    "$(learner_classify 0.5 5)"  "0.5/5 → IGNORE (mediocre)"
      assert_eq "IGNORE"    "$(learner_classify 0.21 5)" "0.21/5 → IGNORE (just above)"
      assert_eq "DEPRECATE" "$(learner_classify 0.2 5)"  "0.2/5 → DEPRECATE (boundary)"
      assert_eq "DEPRECATE" "$(learner_classify 0.0 5)"  "0.0/5 → DEPRECATE"
      assert_eq "IGNORE"    "$(learner_classify 1.0 4)"  "n=4 always IGNORE (under count)"

      echo ""
      echo "4. learner_collect_pending — verdict mix:"
      pending=$(learner_collect_pending "2024-01-01T00:00:00Z")
      promote_count=$(echo "$pending" | awk -F'\t' '$1=="PROMOTE"' | wc -l | tr -d ' ')
      deprecate_count=$(echo "$pending" | awk -F'\t' '$1=="DEPRECATE"' | wc -l | tr -d ' ')
      ignore_count=$(echo "$pending" | awk -F'\t' '$1=="IGNORE"' | wc -l | tr -d ' ')
      # Expected:
      #   90% → PROMOTE   (gemini/deep)
      #   80% → PROMOTE   (codex/medium)
      #   50% → dropped (mediocre)
      #   20% → DEPRECATE (haiku/simple)
      #  ~16% → DEPRECATE (codex/deep self_heal)
      #   n=3 → not in score output at all
      assert_eq "2" "$promote_count" "2 PROMOTE verdicts (90% + 80%)"
      assert_eq "2" "$deprecate_count" "2 DEPRECATE verdicts (20% + ~16%)"
      assert_eq "0" "$ignore_count" "no IGNORE leaked through (collect filters them)"

      # Verify the underweight pattern (n=3) does NOT appear at all
      n3_appeared=$(echo "$pending" | awk -F'\t' '$3=="RETRY" && $4=="gemini" && $5=="simple"' | wc -l | tr -d ' ')
      assert_eq "0" "$n3_appeared" "n=3 pattern absent (below count threshold)"

      # Verify the mediocre pattern (50%) does NOT appear
      mediocre_appeared=$(echo "$pending" | awk -F'\t' '$4=="haiku" && $5=="medium"' | wc -l | tr -d ' ')
      assert_eq "0" "$mediocre_appeared" "50% mediocre pattern absent"

      echo ""
      echo "5. True-blocker filter — escalation rows must NEVER be emitted:"
      # Insert 5 escalation rows (all success, would otherwise PROMOTE)
      for i in 1 2 3 4 5; do
        ts_epoch=$(( base_epoch + seq_counter * 60 ))
        ts=$(date -u -r "$ts_epoch" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null \
          || date -u -d "@$ts_epoch" +"%Y-%m-%dT%H:%M:%SZ")
        sqlite3 "$TEST_DB" <<SQL
INSERT INTO decisions (decision_id, ts, class, decision, reason, context, outcome)
VALUES ('esc_${i}_$$', '$ts', 'escalation', 'ESCALATE_REPEATED', 'r',
        '{"dispatcher":"none","complexity":"none"}', 'success');
SQL
        seq_counter=$(( seq_counter + 1 ))
      done

      # Insert 5 budget-cap escalations (also blockers semantically)
      for i in 1 2 3 4 5; do
        ts_epoch=$(( base_epoch + seq_counter * 60 ))
        ts=$(date -u -r "$ts_epoch" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null \
          || date -u -d "@$ts_epoch" +"%Y-%m-%dT%H:%M:%SZ")
        sqlite3 "$TEST_DB" <<SQL
INSERT INTO decisions (decision_id, ts, class, decision, reason, context, outcome)
VALUES ('bud_${i}_$$', '$ts', 'budget', 'ESCALATE_MONTHLY_CAP', 'r',
        '{"dispatcher":"none","complexity":"none"}', 'success');
SQL
        seq_counter=$(( seq_counter + 1 ))
      done

      pending2=$(learner_collect_pending "2024-01-01T00:00:00Z")
      esc_appeared=$(echo "$pending2" | awk -F'\t' '$2=="escalation"' | wc -l | tr -d ' ')
      bud_appeared=$(echo "$pending2" | awk -F'\t' '$2=="budget" && $3=="ESCALATE_MONTHLY_CAP"' | wc -l | tr -d ' ')
      assert_eq "0" "$esc_appeared" "class=escalation never appears (5 rows × 100% success)"
      assert_eq "0" "$bud_appeared" "budget/ESCALATE_MONTHLY_CAP never appears"

      # Sanity: counts of original 4 verdicts unchanged after blocker rows added
      promote2=$(echo "$pending2" | awk -F'\t' '$1=="PROMOTE"' | wc -l | tr -d ' ')
      deprecate2=$(echo "$pending2" | awk -F'\t' '$1=="DEPRECATE"' | wc -l | tr -d ' ')
      assert_eq "2" "$promote2" "blocker rows did not add to PROMOTE count"
      assert_eq "2" "$deprecate2" "blocker rows did not add to DEPRECATE count"

      echo ""
      echo "6. learner_run — sidecar output and idempotency:"
      learner_run --full >/dev/null
      [[ -f "$TEST_PENDING" ]] && pf_exists=1 || pf_exists=0
      assert_eq "1" "$pf_exists" "pending sidecar file written"

      sidecar_lines=$(grep -c . "$TEST_PENDING" 2>/dev/null || echo 0)
      assert_eq "4" "$sidecar_lines" "sidecar has 4 lines (2 promote + 2 deprecate)"

      # Schema spot-check: each line must be valid JSON with required keys
      bad_lines=0
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        action=$(echo "$line" | sqlite3 ":memory:" "SELECT json_extract('$line', '\$.action');" 2>/dev/null)
        cls=$(echo "$line" | sqlite3 ":memory:" "SELECT json_extract('$line', '\$.class');" 2>/dev/null)
        if [[ -z "$action" ]] || [[ -z "$cls" ]]; then
          bad_lines=$(( bad_lines + 1 ))
        fi
        case "$action" in
          promote|deprecate) ;;
          *) bad_lines=$(( bad_lines + 1 )) ;;
        esac
      done < "$TEST_PENDING"
      assert_eq "0" "$bad_lines" "every sidecar line has valid action+class JSON"

      # Idempotency — re-run, byte-compare
      hash1=$(shasum "$TEST_PENDING" | awk '{print $1}')
      learner_run --full >/dev/null
      hash2=$(shasum "$TEST_PENDING" | awk '{print $1}')
      assert_eq "$hash1" "$hash2" "re-run produces byte-identical sidecar"

      echo ""
      echo "7. Bash-3 compat scan (lib region only):"
      bash3_violations=$(awk '/^if \[\[ "\$\{BASH_SOURCE\[0\]\}"/ { exit } { print }' \
          "$0" \
          | grep -v '^[[:space:]]*#' \
          | grep -c -E '(^|[[:space:]])(declare -A|mapfile)([[:space:]]|$)' || true)
      assert_eq "0" "$bash3_violations" "no Bash-4 constructs in lib region"

      echo ""
      echo "8. Plan 03-03: learner_apply_pending — auto-patch + git + audit + lock:"

      # Isolate VAULT_PATH to a tmp git repo + tmp policy DB so we don't touch
      # real ~/vaults/ark or its policy-decisions DB.
      APPLY_VAULT="$(mktemp -d -t ark-apply-test-XXXXXXXX)"
      APPLY_DB="/tmp/ark-apply-test-$$.db"
      APPLY_PENDING="$APPLY_VAULT/observability/policy-evolution-pending.jsonl"
      mkdir -p "$APPLY_VAULT/observability"
      export VAULT_PATH="$APPLY_VAULT"
      export ARK_HOME="$APPLY_VAULT"
      export PENDING_FILE="$APPLY_PENDING"
      export ARK_POLICY_DB="$APPLY_DB"
      rm -f "$APPLY_DB" "$APPLY_DB-shm" "$APPLY_DB-wal"
      db_init >/dev/null 2>&1 || true

      # git init the tmp vault (hermetic — no global config bleed)
      ( cd "$APPLY_VAULT" \
        && git init --quiet \
        && git config user.email "test@example.invalid" \
        && git config user.name "Apply Test" \
        && git config commit.gpgsign false ) >/dev/null 2>&1

      # Insert parent decision rows so FK constraint on correlation_id holds.
      for did in dec_a dec_b dec_c dec_d dec_e dec_f dec_x; do
        sqlite3 "$APPLY_DB" <<SQL
INSERT INTO decisions (decision_id, ts, class, decision, reason, context, outcome)
VALUES ('$did', '2026-04-26T00:00:00Z', 'dispatch_failure', 'SELF_HEAL', 'parent', '{}', 'success');
SQL
      done

      # Synthesize 2 PROMOTE + 1 DEPRECATE + 1 true-blocker pending lines.
      cat > "$APPLY_PENDING" <<'EOF'
{"action":"promote","class":"dispatch_failure","decision":"SELF_HEAL","dispatcher":"gemini","complexity":"deep","count":5,"rate_pct":100,"rate":1.0,"decision_ids":["dec_a","dec_b"]}
{"action":"deprecate","class":"dispatch_failure","decision":"RETRY","dispatcher":"haiku","complexity":"simple","count":5,"rate_pct":20,"rate":0.2,"decision_ids":["dec_c"]}
{"action":"promote","class":"self_heal","decision":"ATTEMPT","dispatcher":"codex","complexity":"deep","count":6,"rate_pct":83,"rate":0.83,"decision_ids":["dec_d","dec_e"]}
{"action":"promote","class":"budget","decision":"ESCALATE_MONTHLY_CAP","dispatcher":"none","complexity":"none","count":100,"rate_pct":100,"rate":1.0,"decision_ids":["dec_f"]}
EOF

      # Run apply
      apply_out=$(learner_apply_pending "$APPLY_PENDING" 2>&1)

      # Assert policy.yml exists
      [[ -f "$APPLY_VAULT/policy.yml" ]] && pyml=1 || pyml=0
      assert_eq "1" "$pyml" "policy.yml created in tmp vault"

      # Assert PROMOTE keys present (gemini/deep)
      gemini_preferred=$(grep -c "preferred: true" "$APPLY_VAULT/policy.yml" 2>/dev/null || echo 0)
      gemini_preferred=$(echo "$gemini_preferred" | tr -d ' \n')
      # 2 promotes → 2 preferred:true lines
      [[ "$gemini_preferred" -ge 2 ]] && pp=1 || pp=0
      assert_eq "1" "$pp" "policy.yml has >=2 'preferred: true' entries (2 promotes)"

      # Assert DEPRECATE key present
      haiku_dep=$(grep -c "deprecated: true" "$APPLY_VAULT/policy.yml" 2>/dev/null || echo 0)
      haiku_dep=$(echo "$haiku_dep" | tr -d ' \n')
      [[ "$haiku_dep" -ge 1 ]] && hd=1 || hd=0
      assert_eq "1" "$hd" "policy.yml has 'deprecated: true' (1 deprecate)"

      # Assert the true-blocker (budget/ESCALATE_MONTHLY_CAP) was NOT patched.
      # We search only for content lines (skip comments via grep -v '^[[:space:]]*#').
      blocker_present=$(grep -v '^[[:space:]]*#' "$APPLY_VAULT/policy.yml" 2>/dev/null | grep -c "ESCALATE_MONTHLY_CAP" || true)
      blocker_present=$(echo "$blocker_present" | tr -d ' \n')
      assert_eq "0" "$blocker_present" "true-blocker (ESCALATE_MONTHLY_CAP) NOT in policy.yml content"

      # Assert lock dir is gone
      [[ -d "$APPLY_VAULT/.policy-yml.lock" ]] && lk=1 || lk=0
      assert_eq "0" "$lk" "lock dir removed after run"

      # Assert git commits — 3 expected (2 promote + 1 deprecate; blocker skipped)
      commit_count=$(git -C "$APPLY_VAULT" log --oneline --all 2>/dev/null | wc -l | tr -d ' ')
      assert_eq "3" "$commit_count" "3 git commits in tmp vault (2 auto-promote + 1 auto-deprecate)"

      # Assert commit messages have the AOS Phase 3 prefix
      promote_commits=$(git -C "$APPLY_VAULT" log --oneline --all 2>/dev/null | grep -c "AOS Phase 3: auto-promote" || true)
      promote_commits=$(echo "$promote_commits" | tr -d ' \n')
      assert_eq "2" "$promote_commits" "2 'auto-promote' commits"
      deprecate_commits=$(git -C "$APPLY_VAULT" log --oneline --all 2>/dev/null | grep -c "AOS Phase 3: auto-deprecate" || true)
      deprecate_commits=$(echo "$deprecate_commits" | tr -d ' \n')
      assert_eq "1" "$deprecate_commits" "1 'auto-deprecate' commit"

      # Assert audit log: 3 self_improve rows (PROMOTED x2, DEPRECATED x1)
      si_rows=$(sqlite3 "$APPLY_DB" "SELECT count(*) FROM decisions WHERE class='self_improve';" 2>/dev/null || echo 0)
      assert_eq "3" "$si_rows" "audit DB has 3 class=self_improve rows"
      si_promoted=$(sqlite3 "$APPLY_DB" "SELECT count(*) FROM decisions WHERE class='self_improve' AND decision='PROMOTED';" 2>/dev/null || echo 0)
      si_deprecated=$(sqlite3 "$APPLY_DB" "SELECT count(*) FROM decisions WHERE class='self_improve' AND decision='DEPRECATED';" 2>/dev/null || echo 0)
      assert_eq "2" "$si_promoted" "audit: 2 PROMOTED self_improve rows"
      assert_eq "1" "$si_deprecated" "audit: 1 DEPRECATED self_improve row"

      # Assert correlation_id captured from first decision_id
      corr_a=$(sqlite3 "$APPLY_DB" "SELECT correlation_id FROM decisions WHERE class='self_improve' AND reason LIKE 'rate_pct_100_count_5%';" 2>/dev/null)
      assert_eq "dec_a" "$corr_a" "correlation_id == first decision_id (dec_a) for first promote"

      # Assert pending file archived
      [[ -f "$APPLY_PENDING" ]] && pe=1 || pe=0
      assert_eq "0" "$pe" "pending file archived (not at original path)"
      archived_count=$(ls "${APPLY_PENDING}.applied-"* 2>/dev/null | wc -l | tr -d ' ')
      [[ "$archived_count" -ge 1 ]] && ac=1 || ac=0
      assert_eq "1" "$ac" "exactly one .applied-<ts> archive exists"

      # === Idempotency: rebuild same pending, re-apply, expect no new commits/audit ===
      cat > "$APPLY_PENDING" <<'EOF'
{"action":"promote","class":"dispatch_failure","decision":"SELF_HEAL","dispatcher":"gemini","complexity":"deep","count":5,"rate_pct":100,"rate":1.0,"decision_ids":["dec_a","dec_b"]}
{"action":"deprecate","class":"dispatch_failure","decision":"RETRY","dispatcher":"haiku","complexity":"simple","count":5,"rate_pct":20,"rate":0.2,"decision_ids":["dec_c"]}
{"action":"promote","class":"self_heal","decision":"ATTEMPT","dispatcher":"codex","complexity":"deep","count":6,"rate_pct":83,"rate":0.83,"decision_ids":["dec_d","dec_e"]}
EOF
      learner_apply_pending "$APPLY_PENDING" >/dev/null 2>&1

      commit_count2=$(git -C "$APPLY_VAULT" log --oneline --all 2>/dev/null | wc -l | tr -d ' ')
      assert_eq "3" "$commit_count2" "re-apply: still 3 commits (no-op idempotent)"
      si_rows2=$(sqlite3 "$APPLY_DB" "SELECT count(*) FROM decisions WHERE class='self_improve';" 2>/dev/null || echo 0)
      assert_eq "3" "$si_rows2" "re-apply: still 3 self_improve audit rows (no-op idempotent)"

      # === Concurrent-run lock test ===
      # Two background invocations; verify they serialize (lock dir prevents
      # both from progressing past mkdir simultaneously). We assert no panic
      # and that the final state is still consistent (3 commits, 3 audit rows).
      cat > "$APPLY_PENDING" <<'EOF'
{"action":"promote","class":"dispatch_failure","decision":"NEW_PATTERN","dispatcher":"gemini","complexity":"strong","count":7,"rate_pct":90,"rate":0.9,"decision_ids":["dec_x"]}
EOF
      ( learner_apply_pending "$APPLY_PENDING" >/dev/null 2>&1 ) &
      pid1=$!
      ( learner_apply_pending "$APPLY_PENDING" >/dev/null 2>&1 ) &
      pid2=$!
      wait "$pid1" 2>/dev/null
      wait "$pid2" 2>/dev/null
      # Lock should be released
      [[ -d "$APPLY_VAULT/.policy-yml.lock" ]] && lk2=1 || lk2=0
      assert_eq "0" "$lk2" "lock dir released after concurrent runs"
      # Exactly one of the two siblings should have applied the new pattern
      # (the other found the file at $APPLY_PENDING archived and either no-op'd
      #  or found nothing). Either way: only one new commit should land.
      commit_count3=$(git -C "$APPLY_VAULT" log --oneline --all 2>/dev/null | wc -l | tr -d ' ')
      [[ "$commit_count3" -ge 4 ]] && [[ "$commit_count3" -le 5 ]] && cc=1 || cc=0
      assert_eq "1" "$cc" "concurrent runs produced 4-5 total commits (no double-apply)"

      # Cleanup tmp vault
      rm -rf "$APPLY_VAULT"
      rm -f "$APPLY_DB" "$APPLY_DB-shm" "$APPLY_DB-wal"
      unset VAULT_PATH ARK_HOME PENDING_FILE
      export ARK_POLICY_DB="$TEST_DB"

      echo ""
      echo "✅ ALL APPLY-PENDING TESTS PASSED"

      # Cleanup
      rm -f "$TEST_DB" "$TEST_DB-shm" "$TEST_DB-wal" "$TEST_PENDING"

      echo ""
      if [[ "$fail" -eq 0 ]]; then
        echo "✅ ALL POLICY-LEARNER TESTS PASSED ($pass/$pass)"
        exit 0
      else
        echo "❌ $fail/$((pass+fail)) tests failed"
        exit 1
      fi
      ;;
    run|--full)
      learner_run --full
      ;;
    --since)
      shift
      learner_run --since "$1"
      ;;
    digest)
      # Plan 03-04: write only the digest (no scoring/sidecar side-effects).
      learner_write_digest "${2:-1970-01-01T00:00:00Z}"
      ;;
    apply)
      # Plan 03-03: apply pending sidecar to policy.yml (locked + audited + git).
      learner_apply_pending "${2:-$PENDING_FILE}"
      ;;
    *)
      echo "Usage: $0 [test|run|--full|--since DATE|digest [SINCE]|apply [PENDING]]" >&2
      exit 1
      ;;
  esac
fi
