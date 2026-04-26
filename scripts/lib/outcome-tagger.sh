#!/usr/bin/env bash
# outcome-tagger.sh — SINGLE writer for the `outcome` field of the policy decisions DB.
#
# Phase 3 Plan 03-01 (REQ-AOS-09). Reads delivery logs + git history within a
# configurable window of each decision_id's timestamp, and patches the `outcome`
# column via SQL UPDATE. Mirror of Phase 2's _policy_log single-writer rule:
#   - _policy_log         → SOLE writer for INSERTs (new rows)
#   - outcome-tagger.sh   → SOLE writer for UPDATEs to the `outcome` field
#
# Substrate: SQLite (Phase 2.5). Schema is LOCKED at schema_version=1.
# This file does NOT touch schema_version, decision_id, ts, class, decision,
# reason, context, or correlation_id. Only `outcome`.
#
# Bash 3 compatible (macOS default). NO associative arrays, NO mapfile, NO
# `set -euo pipefail` at top — sourced lib must not break callers.

# Locate sibling lib dir (works whether sourced or executed directly)
_OT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

# Source the SQLite backend lib for db_path()
# shellcheck disable=SC1091
if [[ -f "$_OT_LIB_DIR/policy-db.sh" ]]; then
  source "$_OT_LIB_DIR/policy-db.sh"
fi

# Optional cascading config (graceful degradation)
# shellcheck disable=SC1091
if [[ -f "$_OT_LIB_DIR/policy-config.sh" ]]; then
  source "$_OT_LIB_DIR/policy-config.sh"
elif ! type policy_config_get >/dev/null 2>&1; then
  policy_config_get() { echo "$2"; }
fi

# Default window in minutes (env override > config > 10)
_ot_window_minutes() {
  if [[ -n "${ARK_TAGGER_WINDOW_MIN:-}" ]]; then
    echo "$ARK_TAGGER_WINDOW_MIN"
    return
  fi
  policy_config_get phase3.outcome_window_minutes 10
}

# SQL-escape a single value (single-quote → doubled). Echoes escaped string.
_ot_sql_escape() {
  printf "%s" "$1" | sed "s/'/''/g"
}

# Convert ISO8601 (UTC, ...Z) to epoch seconds. macOS BSD date with GNU fallback.
_ot_to_epoch() {
  local iso="$1"
  local e
  e=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$iso" +%s 2>/dev/null) && { echo "$e"; return 0; }
  e=$(date -u -d "$iso" +%s 2>/dev/null) && { echo "$e"; return 0; }
  return 1
}

# Convert epoch → ISO8601 UTC
_ot_from_epoch() {
  local epoch="$1"
  date -u -r "$epoch" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -d "@$epoch" +"%Y-%m-%dT%H:%M:%SZ"
}

# Look up the ts of a decision_id from the DB.
_ot_lookup_ts() {
  local decision_id="$1"
  local e_did; e_did="$(_ot_sql_escape "$decision_id")"
  sqlite3 "$(db_path)" "SELECT ts FROM decisions WHERE decision_id='$e_did' LIMIT 1;"
}

# Look up correlation_id, class for a decision (used to detect failure chains)
_ot_lookup_class() {
  local decision_id="$1"
  local e_did; e_did="$(_ot_sql_escape "$decision_id")"
  sqlite3 "$(db_path)" "SELECT class FROM decisions WHERE decision_id='$e_did' LIMIT 1;"
}

# Public: tagger_infer_outcome <decision_id> [project_dir] [window_minutes]
# Echoes one of: success | failure | ambiguous
# Heuristic:
#   - failure if any later decision exists with class='escalation' AND
#     correlation_id == this decision_id within the window
#   - success if a git commit landed in project_dir within the window AND
#     no escalation chain exists for this decision_id
#   - ambiguous otherwise
tagger_infer_outcome() {
  local decision_id="$1"
  local project_dir="${2:-${ARK_TAGGER_PROJECT_DIR:-$PWD}}"
  local window_min="${3:-$(_ot_window_minutes)}"

  if [[ -z "$decision_id" ]]; then
    echo "tagger_infer_outcome: decision_id required" >&2
    return 2
  fi

  local ts
  ts="$(_ot_lookup_ts "$decision_id")"
  if [[ -z "$ts" ]]; then
    echo "tagger_infer_outcome: decision_id $decision_id not found in DB" >&2
    echo "ambiguous"
    return 0
  fi

  local epoch_start epoch_end
  epoch_start="$(_ot_to_epoch "$ts")" || { echo "ambiguous"; return 0; }
  epoch_end=$(( epoch_start + window_min * 60 ))
  local until_iso; until_iso="$(_ot_from_epoch "$epoch_end")"

  local e_did; e_did="$(_ot_sql_escape "$decision_id")"
  local e_ts; e_ts="$(_ot_sql_escape "$ts")"
  local e_until; e_until="$(_ot_sql_escape "$until_iso")"

  # Failure: an escalation row in this chain after `ts` and within window
  local fail_count
  fail_count=$(sqlite3 "$(db_path)" \
    "SELECT COUNT(*) FROM decisions
     WHERE class='escalation'
       AND correlation_id='$e_did'
       AND ts > '$e_ts'
       AND ts <= '$e_until';")
  if [[ "${fail_count:-0}" -gt 0 ]]; then
    echo "failure"
    return 0
  fi

  # Failure (alt): a self_heal REJECTED in chain
  local heal_reject
  heal_reject=$(sqlite3 "$(db_path)" \
    "SELECT COUNT(*) FROM decisions
     WHERE class='self_heal'
       AND decision='REJECTED'
       AND correlation_id='$e_did'
       AND ts > '$e_ts'
       AND ts <= '$e_until';")
  if [[ "${heal_reject:-0}" -gt 0 ]]; then
    echo "failure"
    return 0
  fi

  # Success heuristics:
  #   1) A delivery log under project_dir/.planning/delivery-logs/ contains
  #      a "success" or "complete" marker for this decision_id, OR
  #   2) A git commit landed in project_dir within the window AND no failure
  #      signal (already filtered above), OR
  #   3) A subsequent decision in the same correlation chain has decision
  #      != ESCALATE_* (i.e., the system kept going without escalating)
  local success=0

  # Delivery-log scan (if dir exists)
  local log_dir="$project_dir/.planning/delivery-logs"
  if [[ -d "$log_dir" ]]; then
    if grep -lE "$decision_id.*(success|complete|PROMOTED)" "$log_dir"/*.log >/dev/null 2>&1; then
      success=1
    fi
  fi

  # Git commit signal — only for dispatch-flavoured classes. Budget/zero_tasks
  # decisions don't directly produce code, so a coincident commit isn't evidence.
  if [[ "$success" -eq 0 ]] && [[ -d "$project_dir/.git" ]]; then
    local cls; cls="$(_ot_lookup_class "$decision_id")"
    case "$cls" in
      dispatch|dispatch_failure|self_heal|self_improve)
        local commits
        commits=$(git -C "$project_dir" log \
          --since="$ts" --until="$until_iso" \
          --pretty=oneline 2>/dev/null | head -1)
        if [[ -n "$commits" ]]; then
          success=1
        fi
        ;;
    esac
  fi

  # Chain follow-up signal
  if [[ "$success" -eq 0 ]]; then
    local chain_followup
    chain_followup=$(sqlite3 "$(db_path)" \
      "SELECT COUNT(*) FROM decisions
       WHERE correlation_id='$e_did'
         AND decision NOT LIKE 'ESCALATE_%'
         AND ts > '$e_ts'
         AND ts <= '$e_until';")
    if [[ "${chain_followup:-0}" -gt 0 ]]; then
      success=1
    fi
  fi

  if [[ "$success" -eq 1 ]]; then
    echo "success"
  else
    echo "ambiguous"
  fi
}

# Public: tagger_patch_outcome <decision_id> <outcome>
# Idempotent UPDATE of the outcome column.
#   - 0: patched (was NULL, now set) OR no-op (already matches)
#   - 1: no-op (already matches — separate exit code reserved; we collapse to 0)
#   - 2: conflict (existing outcome differs from requested AND ARK_TAGGER_FORCE != true)
tagger_patch_outcome() {
  local decision_id="$1"
  local outcome="$2"

  if [[ -z "$decision_id" ]] || [[ -z "$outcome" ]]; then
    echo "tagger_patch_outcome: decision_id and outcome required" >&2
    return 2
  fi
  case "$outcome" in
    success|failure|ambiguous) ;;
    *)
      echo "tagger_patch_outcome: invalid outcome '$outcome' (success|failure|ambiguous)" >&2
      return 2
      ;;
  esac

  local e_did; e_did="$(_ot_sql_escape "$decision_id")"
  local e_out; e_out="$(_ot_sql_escape "$outcome")"

  local existing
  existing=$(sqlite3 "$(db_path)" "SELECT IFNULL(outcome, '') FROM decisions WHERE decision_id='$e_did' LIMIT 1;")

  if [[ -z "$existing" ]]; then
    # Either row missing OR outcome IS NULL (existing == ''). Disambiguate.
    local exists
    exists=$(sqlite3 "$(db_path)" "SELECT COUNT(*) FROM decisions WHERE decision_id='$e_did';")
    if [[ "$exists" -eq 0 ]]; then
      echo "tagger_patch_outcome: decision_id $decision_id not found" >&2
      return 2
    fi
    # Row exists, outcome IS NULL → patch it
    sqlite3 "$(db_path)" "UPDATE decisions SET outcome='$e_out' WHERE decision_id='$e_did' AND outcome IS NULL;"
    return 0
  fi

  if [[ "$existing" == "$outcome" ]]; then
    # Already correct — true no-op
    return 0
  fi

  # Existing differs
  if [[ "${ARK_TAGGER_FORCE:-false}" == "true" ]]; then
    sqlite3 "$(db_path)" "UPDATE decisions SET outcome='$e_out' WHERE decision_id='$e_did';"
    return 0
  fi

  echo "tagger_patch_outcome: $decision_id has outcome='$existing', refusing overwrite to '$outcome' (set ARK_TAGGER_FORCE=true to override)" >&2
  return 2
}

# Public: tagger_run_window <since_iso8601> [until_iso8601]
# Iterates every decision row with outcome IS NULL and ts >= since (and < until
# if provided). Calls tagger_infer_outcome + tagger_patch_outcome for each.
# Echoes summary line: "tagged: N (success: a, failure: b, ambiguous: c)".
tagger_run_window() {
  local since="$1"
  local until="${2:-}"

  if [[ -z "$since" ]]; then
    echo "tagger_run_window: since_iso8601 required" >&2
    return 2
  fi

  local e_since; e_since="$(_ot_sql_escape "$since")"
  local where="outcome IS NULL AND ts >= '$e_since'"
  if [[ -n "$until" ]]; then
    local e_until; e_until="$(_ot_sql_escape "$until")"
    where="$where AND ts < '$e_until'"
  fi

  # Collect candidate decision_ids (Bash 3 — use a temp file)
  local tmp_ids="/tmp/ot_run_$$.ids"
  sqlite3 "$(db_path)" "SELECT decision_id FROM decisions WHERE $where ORDER BY ts ASC;" > "$tmp_ids"

  local n=0 a=0 b=0 c=0
  local did verdict rc
  while IFS= read -r did; do
    [[ -z "$did" ]] && continue
    verdict="$(tagger_infer_outcome "$did")"
    tagger_patch_outcome "$did" "$verdict"
    rc=$?
    if [[ "$rc" -eq 0 ]]; then
      n=$(( n + 1 ))
      case "$verdict" in
        success)   a=$(( a + 1 )) ;;
        failure)   b=$(( b + 1 )) ;;
        ambiguous) c=$(( c + 1 )) ;;
      esac
    fi
  done < "$tmp_ids"

  rm -f "$tmp_ids"
  echo "tagged: $n (success: $a, failure: $b, ambiguous: $c)"
}

# === Self-test ===
if [[ "${BASH_SOURCE[0]}" == "${0}" ]] && [[ "${1:-}" == "test" ]]; then
  echo "🧪 outcome-tagger.sh self-test"
  echo ""

  # Isolated tmp DB + tmp project dir
  TEST_DB="/tmp/ark-tagger-test-$$.db"
  TEST_PROJ="/tmp/ark-tagger-proj-$$"
  export ARK_POLICY_DB="$TEST_DB"
  export ARK_TAGGER_PROJECT_DIR="$TEST_PROJ"
  export ARK_TAGGER_WINDOW_MIN=60   # widen window for synthetic data spanning minutes

  rm -rf "$TEST_DB" "$TEST_DB-shm" "$TEST_DB-wal" "$TEST_PROJ"
  mkdir -p "$TEST_PROJ/.planning/delivery-logs"

  # Init schema
  db_init >/dev/null

  # Synthesize 5 decisions:
  #   id_succ_1 — followed by chain decision (PROCEED) within 60 min → success
  #   id_succ_2 — delivery-log marker mentions decision_id success → success
  #   id_succ_3 — git commit within window → success (we'll init a git repo + commit)
  #   id_fail_1 — followed by escalation in chain → failure
  #   id_amb_1  — no signal at all → ambiguous

  base_ts="2026-01-15T12:00:00Z"
  follow_ts_1m="2026-01-15T12:01:00Z"
  follow_ts_5m="2026-01-15T12:05:00Z"
  follow_ts_10m="2026-01-15T12:10:00Z"
  follow_ts_30m="2026-01-15T12:30:00Z"

  sqlite3 "$TEST_DB" <<SQL
INSERT INTO decisions (decision_id, ts, class, decision, reason, context, outcome, correlation_id)
VALUES
  ('id_succ_1', '$base_ts',       'dispatch_failure', 'SELF_HEAL',    'r', NULL, NULL, NULL),
  ('id_succ_1_b','$follow_ts_5m', 'dispatch',         'codex',        'r', NULL, NULL, 'id_succ_1'),
  ('id_succ_2', '$base_ts',       'dispatch_failure', 'RETRY_NEXT_TIER','r', NULL, NULL, NULL),
  ('id_succ_3', '$base_ts',       'dispatch',         'gemini',       'r', NULL, NULL, NULL),
  ('id_fail_1', '$base_ts',       'dispatch_failure', 'SELF_HEAL',    'r', NULL, NULL, NULL),
  ('id_fail_1_b','$follow_ts_10m','escalation',       'ESCALATE_REPEATED','r',NULL,NULL,'id_fail_1'),
  ('id_amb_1',  '$base_ts',       'budget',           'PROCEED',      'r', NULL, NULL, NULL);
SQL

  # Delivery log marker for id_succ_2
  echo "$(date -u +%FT%TZ) id_succ_2 task complete" > "$TEST_PROJ/.planning/delivery-logs/p1.log"

  # Git repo + commit for id_succ_3 within window
  ( cd "$TEST_PROJ" && git init -q && git config user.email t@t && git config user.name t \
      && touch f && git add f \
      && GIT_AUTHOR_DATE="$follow_ts_1m" GIT_COMMITTER_DATE="$follow_ts_1m" \
         git commit -q -m "test commit" )

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

  echo "1. Inference per decision:"
  assert_eq "success"   "$(tagger_infer_outcome id_succ_1)" "id_succ_1 — chain follow-up=success"
  assert_eq "success"   "$(tagger_infer_outcome id_succ_2)" "id_succ_2 — delivery-log marker"
  assert_eq "success"   "$(tagger_infer_outcome id_succ_3)" "id_succ_3 — git commit in window"
  assert_eq "failure"   "$(tagger_infer_outcome id_fail_1)" "id_fail_1 — escalation chain"
  assert_eq "ambiguous" "$(tagger_infer_outcome id_amb_1)"  "id_amb_1 — no signal"

  echo ""
  echo "2. Patch + idempotency:"
  tagger_patch_outcome id_succ_1 success
  v1=$(sqlite3 "$TEST_DB" "SELECT outcome FROM decisions WHERE decision_id='id_succ_1';")
  assert_eq "success" "$v1" "patch id_succ_1 → success persisted"

  # Idempotent re-patch
  tagger_patch_outcome id_succ_1 success
  rc_idempotent=$?
  assert_eq "0" "$rc_idempotent" "re-patch same value → exit 0 (idempotent)"

  # Conflict refused
  tagger_patch_outcome id_succ_1 failure 2>/dev/null
  rc_conflict=$?
  assert_eq "2" "$rc_conflict" "conflicting overwrite without FORCE → exit 2"
  v_after=$(sqlite3 "$TEST_DB" "SELECT outcome FROM decisions WHERE decision_id='id_succ_1';")
  assert_eq "success" "$v_after" "conflict left existing outcome unchanged"

  # FORCE override
  ARK_TAGGER_FORCE=true tagger_patch_outcome id_succ_1 success
  v_force=$(sqlite3 "$TEST_DB" "SELECT outcome FROM decisions WHERE decision_id='id_succ_1';")
  assert_eq "success" "$v_force" "FORCE re-set still success (no regression)"
  # Reset id_succ_1 outcome to NULL so window-run can re-tag it cleanly
  sqlite3 "$TEST_DB" "UPDATE decisions SET outcome=NULL WHERE decision_id='id_succ_1';"

  echo ""
  echo "3. tagger_run_window over synthetic decisions:"
  summary=$(tagger_run_window "2026-01-15T11:00:00Z")
  echo "  summary: $summary"
  # Five primary decisions get tagged. The "_b" rows aren't candidates because
  # they're not in the inference target set OR their inference would also be
  # ambiguous — but they ARE in the window with outcome NULL, so they'll be
  # tagged too (likely ambiguous). We assert the 5 primaries' outcomes directly.
  o1=$(sqlite3 "$TEST_DB" "SELECT outcome FROM decisions WHERE decision_id='id_succ_1';")
  o2=$(sqlite3 "$TEST_DB" "SELECT outcome FROM decisions WHERE decision_id='id_succ_2';")
  o3=$(sqlite3 "$TEST_DB" "SELECT outcome FROM decisions WHERE decision_id='id_succ_3';")
  o4=$(sqlite3 "$TEST_DB" "SELECT outcome FROM decisions WHERE decision_id='id_fail_1';")
  o5=$(sqlite3 "$TEST_DB" "SELECT outcome FROM decisions WHERE decision_id='id_amb_1';")
  assert_eq "success"   "$o1" "run_window tagged id_succ_1=success"
  assert_eq "success"   "$o2" "run_window tagged id_succ_2=success"
  assert_eq "success"   "$o3" "run_window tagged id_succ_3=success"
  assert_eq "failure"   "$o4" "run_window tagged id_fail_1=failure"
  assert_eq "ambiguous" "$o5" "run_window tagged id_amb_1=ambiguous"

  echo ""
  echo "4. Idempotency — re-run produces 0 NEW patches:"
  null_before=$(sqlite3 "$TEST_DB" "SELECT COUNT(*) FROM decisions WHERE outcome IS NULL;")
  summary2=$(tagger_run_window "2026-01-15T11:00:00Z")
  null_after=$(sqlite3 "$TEST_DB" "SELECT COUNT(*) FROM decisions WHERE outcome IS NULL;")
  echo "  re-run summary: $summary2"
  assert_eq "$null_before" "$null_after" "re-run NULL count unchanged"

  echo ""
  echo "5. Schema/Bash-3 invariants:"
  schema_ver=$(sqlite3 "$TEST_DB" "SELECT DISTINCT schema_version FROM decisions;")
  assert_eq "1" "$schema_ver" "schema_version still 1 after patches"

  # Scan only the non-test portion of the lib for Bash-4 constructs (the test
  # block itself contains regex literals that would match its own pattern).
  bash3_violations=$(awk '/^if \[\[ "\$\{BASH_SOURCE\[0\]\}"/ { exit } { print }' \
      "$_OT_LIB_DIR/outcome-tagger.sh" \
      | grep -v '^[[:space:]]*#' \
      | grep -c -E '(^|[[:space:]])(declare -A|mapfile)([[:space:]]|$)' || true)
  assert_eq "0" "$bash3_violations" "no Bash-4 constructs in lib (pre-test region)"

  echo ""
  rm -rf "$TEST_DB" "$TEST_DB-shm" "$TEST_DB-wal" "$TEST_PROJ"

  if [[ "$fail" -eq 0 ]]; then
    echo "✅ ALL OUTCOME-TAGGER TESTS PASSED ($pass/$pass)"
    exit 0
  else
    echo "❌ $fail/$((pass+fail)) tests failed"
    exit 1
  fi
fi
