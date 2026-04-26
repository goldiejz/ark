#!/usr/bin/env bash
# policy-db.sh — SQLite backend for AOS audit log
#
# Sourced by scripts/ark-policy.sh. Initializes ~/vaults/ark/observability/policy.db
# with the locked schema_version=1 contract (decisions table + indexes + WAL pragma).
#
# Phase 2.5 migration target — replaces the pre-existing JSONL append-only log with
# an indexed, transactional, in-place-patchable backend that Phase 3's learner can
# query natively and update via UPDATE WHERE decision_id=...
#
# Bash 3 compatible (macOS default). NO associative arrays, NO regex with capture.
# Sourced library — no top-level set -euo pipefail (would break callers).

db_path() {
    if [[ -n "${ARK_POLICY_DB:-}" ]]; then
        echo "$ARK_POLICY_DB"
    else
        local base="${ARK_HOME:-$HOME/vaults/ark}"
        echo "$base/observability/policy.db"
    fi
}

db_init() {
    local path
    path="$(db_path)"
    mkdir -p "$(dirname "$path")"
    sqlite3 "$path" <<EOF
PRAGMA journal_mode=WAL;
PRAGMA synchronous=NORMAL;
PRAGMA foreign_keys=ON;

CREATE TABLE IF NOT EXISTS decisions (
    decision_id TEXT PRIMARY KEY,
    ts TEXT NOT NULL,
    schema_version INTEGER NOT NULL DEFAULT 1,
    class TEXT NOT NULL,
    decision TEXT NOT NULL,
    reason TEXT NOT NULL,
    context TEXT,
    outcome TEXT,
    correlation_id TEXT REFERENCES decisions(decision_id)
);

CREATE INDEX IF NOT EXISTS idx_decisions_ts ON decisions(ts);
CREATE INDEX IF NOT EXISTS idx_decisions_class ON decisions(class);
CREATE INDEX IF NOT EXISTS idx_decisions_outcome ON decisions(outcome);
CREATE INDEX IF NOT EXISTS idx_decisions_pattern ON decisions(class, decision);
EOF
}

db_insert_decision() {
    local ts="$1"
    local decision_id="$2"
    local class="$3"
    local decision="$4"
    local reason="$5"
    local context="$6"
    local correlation_id="$7"

    local e_ts; e_ts="$(printf "%s" "$ts" | sed "s/'/''/g")"
    local e_did; e_did="$(printf "%s" "$decision_id" | sed "s/'/''/g")"
    local e_cls; e_cls="$(printf "%s" "$class" | sed "s/'/''/g")"
    local e_dcn; e_dcn="$(printf "%s" "$decision" | sed "s/'/''/g")"
    local e_rsn; e_rsn="$(printf "%s" "$reason" | sed "s/'/''/g")"

    local ctx_val="NULL"
    if [[ "$context" != "null" ]] && [[ -n "$context" ]]; then
        local e_ctx; e_ctx="$(printf "%s" "$context" | sed "s/'/''/g")"
        ctx_val="'$e_ctx'"
    fi

    local cid_val="NULL"
    if [[ "$correlation_id" != "null" ]] && [[ -n "$correlation_id" ]]; then
        local e_cid; e_cid="$(printf "%s" "$correlation_id" | sed "s/'/''/g")"
        cid_val="'$e_cid'"
    fi

    sqlite3 "$(db_path)" "PRAGMA foreign_keys=ON; INSERT OR IGNORE INTO decisions (decision_id, ts, class, decision, reason, context, correlation_id) VALUES ('$e_did', '$e_ts', '$e_cls', '$e_dcn', '$e_rsn', $ctx_val, $cid_val);"
}

db_count_decisions() {
    sqlite3 "$(db_path)" "SELECT COUNT(*) FROM decisions;"
}

db_tail_decisions() {
    local n="${1:-20}"
    local path; path="$(db_path)"
    
    if sqlite3 "$path" "SELECT json_object('v', 1);" >/dev/null 2>&1; then
        sqlite3 "$path" "SELECT json_object(
            'decision_id', decision_id,
            'ts', ts,
            'schema_version', schema_version,
            'class', class,
            'decision', decision,
            'reason', reason,
            'context', CASE WHEN context IS NULL THEN NULL ELSE json(context) END,
            'outcome', outcome,
            'correlation_id', correlation_id
        ) FROM decisions ORDER BY ts DESC LIMIT $n;"
    elif sqlite3 -help 2>&1 | grep -q "\-json"; then
        sqlite3 -json "$path" "SELECT * FROM decisions ORDER BY ts DESC LIMIT $n;" | \
            sed -e 's/^\[//' -e 's/\]$//' -e 's/},{/}\n{/g' | grep -v '^$'
    else
        sqlite3 "$path" "SELECT '{ \"decision_id\": \"' || IFNULL(decision_id, '') || '\", \"ts\": \"' || IFNULL(ts, '') || '\", \"class\": \"' || IFNULL(class, '') || '\", \"decision\": \"' || IFNULL(decision, '') || '\", \"reason\": \"' || IFNULL(reason, '') || '\" }' FROM decisions ORDER BY ts DESC LIMIT $n;"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]] && [[ "${1:-}" == "test" ]]; then
    export ARK_POLICY_DB="/tmp/ark_test_$$.db"
    rm -f "$ARK_POLICY_DB"
    
    db_init
    
    db_insert_decision "2024-01-01T00:00:01Z" "id1" "classA" "action1" "reason1" "null" "null"
    db_insert_decision "2024-01-01T00:00:02Z" "id2" "classB" "action2" "reason2" '{"k":"v"}' "null"
    db_insert_decision "2024-01-01T00:00:03Z" "id3" "classA" "action1" "reason3" "null" "id1"
    
    count=$(db_count_decisions)
    if [[ "$count" -ne 3 ]]; then
        echo "❌ Count mismatch: expected 3, got $count"
        exit 1
    fi
    
    db_insert_decision "2024-01-01T00:00:01Z" "id1" "classA" "action1" "reason1" "null" "null"
    count=$(db_count_decisions)
    if [[ "$count" -ne 3 ]]; then
        echo "❌ Duplicate insert failed: count is $count"
        exit 1
    fi
    
    ctx_test='{"path":"/tmp/it'"'"'s"}'
    db_insert_decision "2024-01-01T00:00:04Z" "id4" "classC" "action4" "reason4" "$ctx_test" "null"
    
    ret_ctx=$(sqlite3 "$ARK_POLICY_DB" "SELECT context FROM decisions WHERE decision_id='id4';")
    if [[ "$ret_ctx" != "$ctx_test" ]]; then
        echo "❌ Context round-trip failed: expected $ctx_test, got $ret_ctx"
        exit 1
    fi
    
    tail_out=$(db_tail_decisions 10)
    l_count=$(echo "$tail_out" | grep -v '^$' | wc -l | tr -d ' ')
    if [[ "$l_count" -lt 4 ]]; then
        echo "❌ Tail count mismatch: expected at least 4 lines, got $l_count"
        exit 1
    fi
    
    cid=$(sqlite3 "$ARK_POLICY_DB" "SELECT correlation_id FROM decisions WHERE decision_id='id3';")
    if [[ "$cid" != "id1" ]]; then
        echo "❌ Correlation ID mismatch: expected id1, got $cid"
        exit 1
    fi
    
    rm -f "$ARK_POLICY_DB"
    echo "✅ ALL POLICY-DB TESTS PASSED"
    exit 0
fi
