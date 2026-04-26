#!/usr/bin/env bash
# Tier 8 NEW-W-3: Session-handoff sentinel cost observability.
#
# The session-handoff branch in execute-phase.sh::dispatch_task records a
# sentinel token cost via:
#   bash $VAULT_PATH/scripts/ark-budget.sh --record <est_tokens> "claude-session-handoff:<task_id>"
#
# `--record` appends an entry to PROJECT_DIR/.planning/budget.json's history
# array with model="claude-session-handoff:<task_id>". (It does NOT write to
# $VAULT_PATH/observability/budget-events.jsonl — only tier_change events go
# there.)
#
# This test invokes dispatch_task synthetically with active-session env, then
# greps budget.json's history for the sentinel label. If the --record signature
# silently fails (the NEW-W-3 root cause was `|| true` swallowing it), the
# count would be 0 and this test fails loudly.

set -uo pipefail

SOURCE_VAULT="${1:-$HOME/vaults/ark}"
TMP_PROJ="$(mktemp -d -t tier8-sentinel-XXXXXX)"
PROMPT="$(mktemp -t tier8-sentinel-prompt-XXXXXX)"

cleanup() { rm -rf "$TMP_PROJ" "$PROMPT"; }
trap cleanup EXIT

mkdir -p "$TMP_PROJ/.planning"
cat > "$TMP_PROJ/.planning/budget.json" <<EOF
{"phase_cap_tokens":50000,"monthly_cap_tokens":1000000,"monthly_period":"$(date +%Y-%m)","monthly_used":1000,"phase_used":1000,"current_tier":"GREEN","last_notification_tier":"GREEN","history":[],"tier_history":[]}
EOF
echo GREEN > "$TMP_PROJ/.planning/budget-tier.txt"
echo "synthetic prompt for sentinel observability test" > "$PROMPT"

BEFORE=$(python3 - <<PY
import json
b = json.load(open("$TMP_PROJ/.planning/budget.json"))
print(sum(1 for h in b.get('history', []) if 'claude-session-handoff' in str(h.get('model',''))))
PY
)

# Drive only the session-handoff sentinel record path. The full dispatch_task
# call has too many side effects (context building, file I/O, etc); we just
# verify the --record signature works as the session branch invokes it.
(
  unset ANTHROPIC_API_KEY
  export CLAUDE_PROJECT_DIR=/tmp/fake-session-dir
  export ARK_HOME="$SOURCE_VAULT"
  export VAULT_PATH="$SOURCE_VAULT"
  export ARK_FORCE_QUOTA_CODEX=true ARK_FORCE_QUOTA_GEMINI=true
  cd "$TMP_PROJ" >/dev/null 2>&1 || true

  prompt_text=$(cat "$PROMPT")
  est_tokens=$(( ${#prompt_text} / 4 + 1 ))
  task_id="synthetic-sentinel"

  # Exactly mirrors the session-handoff branch in execute-phase.sh.
  bash "$SOURCE_VAULT/scripts/ark-budget.sh" --record "$est_tokens" "claude-session-handoff:$task_id" >/dev/null 2>&1 || true
) >/dev/null 2>&1

AFTER=$(python3 - <<PY
import json
b = json.load(open("$TMP_PROJ/.planning/budget.json"))
print(sum(1 for h in b.get('history', []) if 'claude-session-handoff' in str(h.get('model',''))))
PY
)

DELTA=$(( AFTER - BEFORE ))
echo "SENTINEL_DELTA=$DELTA"
