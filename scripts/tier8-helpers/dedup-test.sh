#!/usr/bin/env bash
# Tier 8 NEW-W-1: Isolated audit-log dedup test.
#
# Documented call graph for one BLACK-tier dispatch_task call:
#   dispatch_task (BLACK)
#     └─ policy_budget_decision           → 1 class:budget log line (AUTO_RESET)
#         └─ ark-budget.sh --reset
#             └─ python3 zeros phase_used
#             └─ check_and_notify
#                 └─ notify_tier_change(BLACK, GREEN)  (new_tier=GREEN post-zero)
#                     └─ guard `if new_tier == BLACK` is FALSE
#                     └─ NO additional class:budget log line
# Expected DELTA = 1.
#
# Uses an isolated tmp VAULT_PATH so global-log writes from concurrent processes
# cannot poison the BEFORE/AFTER delta.

set -uo pipefail

SOURCE_VAULT="${1:-$HOME/vaults/ark}"
ISO_VAULT="$(mktemp -d -t tier8-iso-XXXXXX)"
TMP_PROJ="$(mktemp -d -t tier8-proj-XXXXXX)"

cleanup() { rm -rf "$ISO_VAULT" "$TMP_PROJ"; }
trap cleanup EXIT

mkdir -p "$ISO_VAULT/scripts/lib" "$ISO_VAULT/observability"
cp "$SOURCE_VAULT/scripts/ark-policy.sh"     "$ISO_VAULT/scripts/" 2>/dev/null
cp "$SOURCE_VAULT/scripts/lib/policy-config.sh" "$ISO_VAULT/scripts/lib/" 2>/dev/null || true
cp "$SOURCE_VAULT/scripts/ark-budget.sh"     "$ISO_VAULT/scripts/" 2>/dev/null
cp "$SOURCE_VAULT/scripts/ark-context.sh"    "$ISO_VAULT/scripts/" 2>/dev/null || true
cp "$SOURCE_VAULT/scripts/ark-escalations.sh" "$ISO_VAULT/scripts/" 2>/dev/null || true
: > "$ISO_VAULT/observability/policy-decisions.jsonl"

mkdir -p "$TMP_PROJ/.planning"
cat > "$TMP_PROJ/.planning/budget.json" <<EOF
{"phase_cap_tokens":50000,"monthly_cap_tokens":1000000,"monthly_period":"2026-04","monthly_used":60000,"phase_used":50000,"current_tier":"BLACK","last_notification_tier":"BLACK","history":[],"tier_history":[]}
EOF
echo BLACK > "$TMP_PROJ/.planning/budget-tier.txt"

# Drive the BLACK-tier branch directly via policy + budget reset, mirroring what
# execute-phase.sh::dispatch_task does on BLACK tier, but without invoking the
# full dispatch_task (which has many irrelevant side effects like building
# context, calling external CLIs, etc). The class:budget audit lines we count
# are exactly the same.
(
  unset ANTHROPIC_API_KEY CLAUDE_PROJECT_DIR
  export ARK_HOME="$ISO_VAULT"
  export VAULT_PATH="$ISO_VAULT"
  export PROJECT_DIR="$TMP_PROJ"
  export ARK_FORCE_QUOTA_CODEX=true ARK_FORCE_QUOTA_GEMINI=true
  cd "$TMP_PROJ" >/dev/null 2>&1 || true

  # shellcheck disable=SC1091
  source "$ISO_VAULT/scripts/ark-policy.sh"

  # Read budget.json for the policy decision args (mirrors dispatch_task).
  read -r PU PC MU MC < <(python3 - <<'PY'
import json, os
b = json.load(open(os.path.join(os.environ['PROJECT_DIR'], '.planning/budget.json')))
print(b['phase_used'], b['phase_cap_tokens'], b['monthly_used'], b['monthly_cap_tokens'])
PY
  )
  decision=$(policy_budget_decision "$PU" "$PC" "$MU" "$MC")
  if [[ "$decision" == "AUTO_RESET" ]]; then
    BUDGET_FILE="$TMP_PROJ/.planning/budget.json" \
      bash "$ISO_VAULT/scripts/ark-budget.sh" --reset >/dev/null 2>&1 || true
  fi
) >/dev/null 2>&1

DELTA=$(grep -c '"class":"budget"' "$ISO_VAULT/observability/policy-decisions.jsonl" 2>/dev/null || echo 0)
DELTA=${DELTA//[[:space:]]/}
echo "DELTA=$DELTA"
