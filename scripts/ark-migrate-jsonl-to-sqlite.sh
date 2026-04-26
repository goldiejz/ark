#!/usr/bin/env bash
# ark-migrate-jsonl-to-sqlite.sh — one-shot JSONL → SQLite migration for AOS audit log
#
# Phase 2.5: Phase 2 shipped policy-decisions.jsonl. Phase 3 needs SQL-grade
# aggregations + in-place outcome patching. This tool imports the existing
# JSONL into the SQLite backend (decisions table). Idempotent — re-running
# inserts only NEW rows (PRIMARY KEY decision_id blocks duplicates).
#
# Usage: bash scripts/ark-migrate-jsonl-to-sqlite.sh
#
# Reads:  $ARK_HOME/observability/policy-decisions.jsonl
# Writes: $ARK_POLICY_DB (default: $ARK_HOME/observability/policy.db)

set -uo pipefail

VAULT_PATH="${ARK_HOME:-$HOME/vaults/ark}"
JSONL="$VAULT_PATH/observability/policy-decisions.jsonl"

# Source the SQLite lib
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
if [[ ! -f "$_LIB_DIR/policy-db.sh" ]]; then
  echo "❌ scripts/lib/policy-db.sh not found — Phase 2.5 lib must be installed first"
  exit 1
fi
# shellcheck disable=SC1091
source "$_LIB_DIR/policy-db.sh"
db_init

if [[ ! -f "$JSONL" ]]; then
  echo "ℹ️  No JSONL log at $JSONL — nothing to migrate"
  echo "   SQLite DB is initialized at $(db_path)"
  exit 0
fi

total=$(wc -l < "$JSONL" | tr -d ' ')
echo "📦 Migrating $total JSONL lines → SQLite..."
echo "   Source: $JSONL"
echo "   Target: $(db_path)"
echo ""

before=$(db_count_decisions)

# Use python to parse each JSON line, then call db_insert_decision per row.
# Single-quoted heredoc + env-var path (no $-interpolation in body).
JSONL="$JSONL" python3 - <<'PY' > /tmp/ark-migrate-rows.tsv
import json, os, sys
src = os.environ['JSONL']
with open(src) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            d = json.loads(line)
        except Exception as e:
            sys.stderr.write(f"skip malformed line: {e}\n")
            continue
        # Required fields
        ts        = d.get('ts', '')
        decision_id = d.get('decision_id', '')
        cls       = d.get('class', '')
        decision  = d.get('decision', '')
        reason    = d.get('reason', '')
        # Optional / nullable
        ctx       = d.get('context', None)
        ctx_str   = json.dumps(ctx) if ctx is not None else 'null'
        corr      = d.get('correlation_id', None)
        corr_str  = corr if corr else 'null'
        # Pre-Phase-2.5 lines may lack decision_id — skip them (can't enforce uniqueness)
        if not decision_id:
            sys.stderr.write(f"skip line without decision_id: {line[:80]}\n")
            continue
        # Tab-separated, escape tabs and newlines in values
        for v in (ts, decision_id, cls, decision, reason, ctx_str, corr_str):
            sys.stdout.write(v.replace('\t', ' ').replace('\n', ' '))
            sys.stdout.write('\t')
        sys.stdout.write('\n')
PY

# Now read the TSV and insert each row
inserted=0
skipped=0
while IFS=$'\t' read -r ts did cls dec reas ctx corr _; do
  [[ -z "$did" ]] && continue
  if db_insert_decision "$ts" "$did" "$cls" "$dec" "$reas" "$ctx" "$corr" 2>/dev/null; then
    inserted=$((inserted + 1))
  else
    skipped=$((skipped + 1))
  fi
done < /tmp/ark-migrate-rows.tsv

after=$(db_count_decisions)
delta=$((after - before))

rm -f /tmp/ark-migrate-rows.tsv

echo ""
echo "✅ Migration complete"
echo "   Rows in DB before: $before"
echo "   Rows in DB after:  $after  (+$delta)"
echo "   Inserted: $inserted, Skipped (dup or malformed): $skipped"
echo ""
echo "Note: JSONL file is preserved at $JSONL (read-only reference)."
echo "      All future _policy_log writes go to $(db_path)."
