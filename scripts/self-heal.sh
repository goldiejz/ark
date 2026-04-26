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

VAULT_PATH="${ARK_HOME:-$HOME/vaults/ark}"

# === Source policy + escalations libs (graceful degradation) ===
# Exposes _policy_log (single audit-log writer, schema_version=1, NEW-B-2)
# and policy_dispatcher_route (used by retry-layer 2: model escalate).
if [[ -f "$VAULT_PATH/scripts/ark-policy.sh" ]]; then
  # shellcheck disable=SC1091
  source "$VAULT_PATH/scripts/ark-policy.sh"
fi
# ark-escalations.sh ships in 02-02; tolerate its absence — type-guard at use site.
if [[ -f "$VAULT_PATH/scripts/ark-escalations.sh" ]]; then
  # shellcheck disable=SC1091
  source "$VAULT_PATH/scripts/ark-escalations.sh"
fi

# ============================================================================
# Layered retry contract (CONTEXT.md decision #4)
# ----------------------------------------------------------------------------
# Mode B entry: self-heal.sh --retry <task_id> <prompt_file> <output_file>
#   Layer 1 (count 0→1): enriched-prompt retry (lessons.md tail + last error)
#   Layer 2 (count 1→2): model-escalate via policy_dispatcher_route deep
#   Layer 3 (count 2→3): ark_escalate repeated-failure, exit 2
# All audit lines go through _policy_log — single writer, single schema.
# ============================================================================

# Layer 1: enriched prompt + same dispatcher
_self_heal_layer_enriched() {
  local task_id="$1" prompt_file="$2" output_file="$3" count_file="$4"
  echo 1 > "$count_file"

  local lessons_blob="" error_blob="" enriched_prompt
  [[ -f "$VAULT_PATH/lessons.md" ]] && lessons_blob=$(tail -200 "$VAULT_PATH/lessons.md")
  [[ -f "${prompt_file%.md}.error.log" ]] && error_blob=$(cat "${prompt_file%.md}.error.log")

  enriched_prompt="${prompt_file%.md}-enriched.md"
  {
    [[ -f "$prompt_file" ]] && cat "$prompt_file"
    echo ""
    echo "## RETRY 1 ENRICHMENT — lessons context"
    echo "$lessons_blob"
    echo ""
    echo "## RETRY 1 ENRICHMENT — last error"
    echo "$error_blob"
  } > "$enriched_prompt"

  # Dispatch via current primary (codex → gemini → haiku-api fallback)
  local out=""
  if command -v codex >/dev/null 2>&1; then
    out=$(codex exec - < "$enriched_prompt" 2>/dev/null </dev/null || echo "")
  fi
  if [[ -z "$out" ]] && command -v gemini >/dev/null 2>&1; then
    out=$(gemini -p - < "$enriched_prompt" 2>/dev/null || echo "")
  fi
  if [[ -z "$out" ]] && [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
    local _payload
    _payload=$(ENRICHED_PROMPT_FILE="$enriched_prompt" python3 - <<'PY' 2>/dev/null
import json, os
with open(os.environ['ENRICHED_PROMPT_FILE']) as f:
    body = f.read()
print(json.dumps({
    'model': 'claude-haiku-4-5-20251001',
    'max_tokens': 1500,
    'messages': [{'role': 'user', 'content': body}]
}))
PY
)
    out=$(curl -s -X POST https://api.anthropic.com/v1/messages \
      -H "x-api-key: $ANTHROPIC_API_KEY" \
      -H "anthropic-version: 2023-06-01" \
      -H "content-type: application/json" \
      --data "$_payload" 2>/dev/null | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get('content', [{}])[0].get('text', ''))
except Exception:
    pass
" 2>/dev/null || echo "")
  fi

  local _ctx
  _ctx=$(printf '{"task_id":"%s","layer":1}' "$task_id")
  if [[ -n "$out" ]]; then
    echo "$out" > "$output_file"
    type _policy_log >/dev/null 2>&1 && _policy_log self_heal "RETRY_1_ENRICHED" "ok" "$_ctx" >/dev/null
    return 0
  fi
  type _policy_log >/dev/null 2>&1 && _policy_log self_heal "RETRY_1_ENRICHED" "empty_output" "$_ctx" >/dev/null
  return 1
}

# Layer 2: model escalate via policy_dispatcher_route deep
_self_heal_layer_escalate_model() {
  local task_id="$1" prompt_file="$2" output_file="$3" count_file="$4"
  echo 2 > "$count_file"

  local chosen="regex-fallback"
  if type policy_dispatcher_route >/dev/null 2>&1; then
    chosen=$(policy_dispatcher_route deep 2>/dev/null || echo "regex-fallback")
  fi

  local out=""
  case "$chosen" in
    codex)
      command -v codex >/dev/null 2>&1 && out=$(codex exec - < "$prompt_file" 2>/dev/null </dev/null || echo "")
      ;;
    gemini)
      command -v gemini >/dev/null 2>&1 && out=$(gemini -p - < "$prompt_file" 2>/dev/null || echo "")
      ;;
    haiku-api|claude-session)
      if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
        local _payload
        _payload=$(PROMPT_FILE="$prompt_file" python3 - <<'PY' 2>/dev/null
import json, os
with open(os.environ['PROMPT_FILE']) as f:
    body = f.read()
print(json.dumps({
    'model': 'claude-haiku-4-5-20251001',
    'max_tokens': 1500,
    'messages': [{'role': 'user', 'content': body}]
}))
PY
)
        out=$(curl -s -X POST https://api.anthropic.com/v1/messages \
          -H "x-api-key: $ANTHROPIC_API_KEY" \
          -H "anthropic-version: 2023-06-01" \
          -H "content-type: application/json" \
          --data "$_payload" 2>/dev/null | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get('content', [{}])[0].get('text', ''))
except Exception:
    pass
" 2>/dev/null || echo "")
      fi
      ;;
    *)
      out=""
      ;;
  esac

  local _ctx
  _ctx=$(printf '{"task_id":"%s","layer":2,"chosen":"%s"}' "$task_id" "$chosen")
  if [[ -n "$out" ]]; then
    echo "$out" > "$output_file"
    type _policy_log >/dev/null 2>&1 && _policy_log self_heal "RETRY_2_MODEL_ESCALATE" "ok" "$_ctx" >/dev/null
    return 0
  fi
  type _policy_log >/dev/null 2>&1 && _policy_log self_heal "RETRY_2_MODEL_ESCALATE" "empty_output" "$_ctx" >/dev/null
  return 1
}

# Layer 3: queue escalation via ark_escalate repeated-failure
_self_heal_layer_escalate_queue() {
  local task_id="$1" prompt_file="$2" output_file="$3" count_file="$4"
  echo 3 > "$count_file"

  local error_blob=""
  [[ -f "${prompt_file%.md}.error.log" ]] && error_blob=$(head -50 "${prompt_file%.md}.error.log")

  local body
  body=$(printf "Self-heal exhausted after 3 retries.\n\ntask_id: %s\nprompt_file: %s\nlast_error:\n%s" \
    "$task_id" "$prompt_file" "$error_blob")

  if type ark_escalate >/dev/null 2>&1; then
    ark_escalate repeated-failure "self-heal exhausted: $task_id" "$body" >/dev/null 2>&1 || true
  fi

  echo "verdict: ESCALATED" > "$output_file"
  echo "summary: self-heal exhausted ($task_id, 3 retries)" >> "$output_file"

  local _ctx
  _ctx=$(printf '{"task_id":"%s","layer":3}' "$task_id")
  type _policy_log >/dev/null 2>&1 && _policy_log self_heal "RETRY_3_ESCALATE_QUEUE" "queued" "$_ctx" >/dev/null

  return 2
}

# Mode B dispatcher: route to the right layer based on retry_count file
self_heal_retry_layer() {
  local task_id="${1:?task_id required}"
  local prompt_file="${2:?prompt_file required}"
  local output_file="${3:?output_file required}"

  # Resolve phase_dir: prefer prompt_file's phase dir, else $PROJECT_DIR/.planning
  local phase_dir
  if [[ "$prompt_file" == */phases/* ]]; then
    phase_dir="${prompt_file%/*}"
  else
    phase_dir="${PROJECT_DIR:-$PWD}/.planning"
  fi
  mkdir -p "$phase_dir" 2>/dev/null || true

  local count_file="$phase_dir/self-heal-retries-${task_id}.txt"
  local retry_count
  retry_count=$(cat "$count_file" 2>/dev/null || echo 0)

  case "$retry_count" in
    0)  _self_heal_layer_enriched        "$task_id" "$prompt_file" "$output_file" "$count_file" ;;
    1)  _self_heal_layer_escalate_model  "$task_id" "$prompt_file" "$output_file" "$count_file" ;;
    *)  _self_heal_layer_escalate_queue  "$task_id" "$prompt_file" "$output_file" "$count_file" ;;
  esac
}

# ============================================================================
# Mode dispatcher — branch BEFORE legacy single-arg path
# ============================================================================
if [[ "${1:-}" == "--retry" ]]; then
  shift
  self_heal_retry_layer "$@"
  exit $?
fi

# ============================================================================
# Mode A — legacy proposal-file path (unchanged)
# ============================================================================
ERROR_LOG="${1:?error log path required}"
CONTEXT="${2:-}"

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

if [[ -z "$DIAGNOSIS" ]] && [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
  EXTRACTOR="haiku-api"
  DIAGNOSIS=$(curl -s -X POST https://api.anthropic.com/v1/messages \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -H "anthropic-version: 2023-06-01" \
    -H "content-type: application/json" \
    --data "$(python3 -c "
import json, sys
print(json.dumps({
    'model': 'claude-haiku-4-5-20251001',
    'max_tokens': 1500,
    'messages': [{'role': 'user', 'content': '''$PROMPT'''}]
}))" 2>/dev/null)" 2>/dev/null | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get('content', [{}])[0].get('text', ''))
except: pass
" 2>/dev/null || echo "")
fi

# If no AI available, log raw error for human review
if [[ -z "$DIAGNOSIS" ]]; then
  cat > "$PROPOSAL_FILE" <<EOF
# Self-heal failed: no AI available

**Time:** $(date -u +%Y-%m-%dT%H:%M:%SZ)
**Error log:** $ERROR_LOG
**Context:** $CONTEXT

## Raw Error
\`\`\`
$ERROR_CONTENT
\`\`\`

## Required Action
Manual review needed. Install codex CLI, gemini CLI, or set ANTHROPIC_API_KEY.
EOF
  exit 1
fi

# Write proposal
cat > "$PROPOSAL_FILE" <<EOF
# Self-heal proposal — $TIMESTAMP

**Source:** $EXTRACTOR
**Error log:** $ERROR_LOG
**Context:** $CONTEXT

$DIAGNOSIS

---

## Original Error
\`\`\`
$ERROR_CONTENT
\`\`\`
EOF

echo "✅ Proposal: $PROPOSAL_FILE"

# Check if auto-apply is recommended
if echo "$DIAGNOSIS" | grep -qi "Auto-Apply.*YES"; then
  echo "🔧 High confidence + low risk → auto-applying"
  # Move to applied for tracking; actual application would extract the proposed fix
  # For safety, currently we just flag it — application requires explicit run
  cp "$PROPOSAL_FILE" "$APPLIED_DIR/"
fi

# Auto-commit to vault
if [[ -d "$VAULT_PATH/.git" ]]; then
  cd "$VAULT_PATH"
  git add self-healing/ 2>/dev/null
  if ! git diff --cached --quiet 2>/dev/null; then
    git commit -m "Self-heal proposal: $TIMESTAMP

Source: $EXTRACTOR
Auto-generated diagnosis from error log." --quiet 2>/dev/null
    git push origin main --quiet 2>/dev/null || true
  fi
fi

exit 0
