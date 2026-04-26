# 02-06b Pre-state — scripts/self-heal.sh

Captured: 2026-04-26 (before refactor)

## File hash + size

```
SHA1: 660598d2559a8f671cc9176d765895b8ba2bef2d
Lines: 162
```

## Caller inventory

```
scripts/ark-doctor.sh:66        — references in health-check loop (existence probe only, not invoked)
scripts/execute-phase.sh:507    — bash "$VAULT_PATH/scripts/self-heal.sh" "$PHASE_DIR/task-$task_num-output.md" "task-$task_num-failure" 2>&1 | tail -5    [LEGACY 2-arg]
scripts/ark-deliver.sh:438      — bash "$VAULT_PATH/scripts/self-heal.sh" "$error_log" "phase-$phase_num-failure" 2>&1                                  [LEGACY 2-arg]
hooks/ark-error-monitor.sh:8    — HEAL_SCRIPT="$VAULT_PATH/scripts/self-heal.sh"  (sets variable; invocation elsewhere in hook flow)
```

All current call sites pass **two args** (`<error_log_path> <context>`). Zero current callers use a 4-arg shape, so the new `--retry` mode is purely additive.

## Pre-refactor self-heal.sh (full)

```bash
#!/usr/bin/env bash
# brain self-heal — auto-diagnose and propose fixes for hook/script failures
#
# Usage: self-heal.sh <error_log_path> [context]
#
# Workflow:
# 1. Read the error log
# 2. Dispatch to cheapest AI for diagnosis
# 3. Write proposed fix to vault/self-healing/proposed/
# 4. If high confidence, auto-apply with backup
# 5. Otherwise log for human review
#
# Cost: ~$0 (Codex/Gemini free tier preferred)

set -uo pipefail

ERROR_LOG="${1:?error log path required}"
CONTEXT="${2:-}"

VAULT_PATH="${ARK_HOME:-$HOME/vaults/ark}"
HEALING_DIR="$VAULT_PATH/self-healing"
PROPOSED_DIR="$HEALING_DIR/proposed"
APPLIED_DIR="$HEALING_DIR/applied"
mkdir -p "$PROPOSED_DIR" "$APPLIED_DIR"

[[ ! -f "$ERROR_LOG" ]] && exit 0

ERROR_CONTENT=$(cat "$ERROR_LOG" | head -100 | head -c 8000)
[[ -z "$ERROR_CONTENT" ]] && exit 0

TIMESTAMP=$(date -u +%Y%m%d-%H%M%S)
PROPOSAL_FILE="$PROPOSED_DIR/heal-$TIMESTAMP.md"

# Build diagnosis prompt
PROMPT='You are a self-healing automation diagnostic agent.

Analyze this error log and produce a structured diagnosis:

ERROR LOG:
'"$ERROR_CONTENT"'

CONTEXT: '"$CONTEXT"'

Output EXACTLY this format:

## Diagnosis
<root cause in one sentence>

## Confidence
<HIGH|MEDIUM|LOW>

## Affected Files
<list of file paths likely needing fix>

## Proposed Fix
<concrete code change OR shell command to fix it>

## Risk
<LOW|MEDIUM|HIGH> — <one sentence why>

## Auto-Apply
<YES|NO> — only YES if confidence is HIGH and risk is LOW

If you cannot diagnose, output: UNKNOWN_ERROR'

# Dispatch to cheapest AI
DIAGNOSIS=""
EXTRACTOR=""

if command -v codex >/dev/null 2>&1; then
  EXTRACTOR="codex"
  DIAGNOSIS=$(echo "$PROMPT" | codex exec - 2>/dev/null </dev/null || echo "")
fi

if [[ -z "$DIAGNOSIS" || "$DIAGNOSIS" == *"UNKNOWN_ERROR"* ]] && command -v gemini >/dev/null 2>&1; then
  EXTRACTOR="gemini"
  DIAGNOSIS=$(echo "$PROMPT" | gemini -p - 2>/dev/null || echo "")
fi

# ... (see scripts/self-heal.sh@660598d for remainder; full content unchanged below)
```

(Truncated for brevity; the full 162-line file lives at SHA1 above. Git has it.)

## Behavior contract today

- 2 args in (error_log, context) → cascade (codex → gemini → haiku-api)
- Writes proposal markdown to `$VAULT_PATH/self-healing/proposed/heal-<ts>.md`
- Auto-commits to vault git
- Always exits 0 unless no AI available (exit 1)

## Post-refactor contract

Adds `--retry <task_id> <prompt_file> <output_file>` mode. Legacy 2-arg path preserved untouched.

Audit logs: ALL `class:self_heal` lines via `_policy_log` from sourced `ark-policy.sh`. NO inline writers. NEW-B-2 enforcement.
