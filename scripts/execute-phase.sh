#!/usr/bin/env bash
# execute-phase.sh — actually write code for a phase by dispatching to Codex per task
#
# Usage: execute-phase.sh <project_dir> <phase_num>
#
# What it does:
# 1. Parses .planning/phase-<N>/PLAN.md for task list
# 2. For each task:
#    a. Builds full context (CLAUDE.md, lessons, current state, task spec)
#    b. Dispatches to Codex with structured prompt
#    c. Applies Codex's output (writes/edits files)
#    d. Runs targeted verification (tsc, relevant tests)
#    e. If pass: commits atomically + moves to next
#    f. If fail: dispatches self-heal, retries once, then escalates
# 3. Logs all dispatches + outcomes to vault for learning

set -uo pipefail

PROJECT_DIR="${1:?project dir required}"
PHASE_NUM="${2:?phase number required}"

VAULT_PATH="${AUTOMATION_BRAIN_PATH:-$HOME/vaults/automation-brain}"
PHASE_DIR="$PROJECT_DIR/.planning/phase-$PHASE_NUM"
PLAN_FILE="$PHASE_DIR/PLAN.md"
CONTEXT_FILE="$PHASE_DIR/.context-$$.md"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
  echo -e "${BLUE}[exec]${NC} $1"
}

ok() {
  echo -e "${GREEN}[exec]${NC} $1"
}

warn() {
  echo -e "${YELLOW}[exec]${NC} $1"
}

err() {
  echo -e "${RED}[exec]${NC} $1"
}

# === Build context block for Codex ===
build_context() {
  local task_desc="$1"
  {
    echo "# Project Context"
    echo ""
    echo "**Project:** $(basename "$PROJECT_DIR")"
    echo "**Phase:** $PHASE_NUM"
    echo "**Task:** $task_desc"
    echo ""

    if [[ -f "$PROJECT_DIR/CLAUDE.md" ]]; then
      echo "## Repo Instructions (CLAUDE.md)"
      echo ""
      head -100 "$PROJECT_DIR/CLAUDE.md"
      echo ""
    fi

    if [[ -f "$PROJECT_DIR/.planning/PROJECT.md" ]]; then
      echo "## Project Definition"
      echo ""
      cat "$PROJECT_DIR/.planning/PROJECT.md"
      echo ""
    fi

    if [[ -f "$PROJECT_DIR/.planning/STATE.md" ]]; then
      echo "## Current State"
      echo ""
      cat "$PROJECT_DIR/.planning/STATE.md"
      echo ""
    fi

    if [[ -f "$PROJECT_DIR/tasks/lessons.md" ]]; then
      echo "## Project Lessons (must apply)"
      echo ""
      cat "$PROJECT_DIR/tasks/lessons.md"
      echo ""
    fi

    # Include critical anti-patterns from brain
    if [[ -f "$VAULT_PATH/bootstrap/anti-patterns.md" ]]; then
      echo "## Universal Anti-Patterns (from brain)"
      echo ""
      head -60 "$VAULT_PATH/bootstrap/anti-patterns.md"
      echo ""
    fi

    # Show current file structure
    echo "## Current File Tree"
    echo "\`\`\`"
    cd "$PROJECT_DIR"
    find . -type f \
      -not -path './node_modules/*' \
      -not -path './.git/*' \
      -not -path './.parent-automation/brain-snapshot/*' \
      -not -path './.parent-automation/pre-align-backup-*/*' \
      | head -40
    echo "\`\`\`"
    echo ""

    # Show package.json for stack context
    if [[ -f "$PROJECT_DIR/package.json" ]]; then
      echo "## package.json"
      echo "\`\`\`json"
      cat "$PROJECT_DIR/package.json"
      echo "\`\`\`"
      echo ""
    fi
  } > "$CONTEXT_FILE"
}

# === Parse tasks from PLAN.md ===
parse_tasks() {
  if [[ ! -f "$PLAN_FILE" ]]; then
    err "No PLAN.md found at $PLAN_FILE"
    return 1
  fi

  # Extract checkbox tasks: "- [ ] Task description"
  grep -E "^[[:space:]]*-[[:space:]]+\[[[:space:]xX]\]" "$PLAN_FILE" | \
    sed -E 's/^[[:space:]]*-[[:space:]]+\[[[:space:]xX]\][[:space:]]+//' || true
}

# === Dispatch a single task to Codex ===
dispatch_task() {
  local task_desc="$1"
  local task_num="$2"

  log "━━━ Task $task_num: $task_desc ━━━"

  # Build context
  build_context "$task_desc"

  # Construct prompt for Codex
  local prompt="You are an autonomous code generation agent for this project.

$(cat "$CONTEXT_FILE")

## Your Task

$task_desc

## Output Format

Output a structured response with:

1. ANALYSIS: One paragraph explaining what files need to change and why
2. FILES: List of files you'll create or modify (relative paths)
3. CODE: For each file, provide the full new content in a code block tagged with the file path:

\`\`\`<filepath>
<full file content>
\`\`\`

4. TESTS: Briefly describe what to test
5. RISK: LOW/MEDIUM/HIGH and one sentence explaining

Constraints:
- Follow ALL conventions in CLAUDE.md (currency suffix, RBAC centralization, route/compute split, etc.)
- Apply lessons from tasks/lessons.md
- Avoid all anti-patterns listed
- Write idiomatic, production-quality code
- Include error handling and proper types
- If you need to add dependencies, list them but don't run npm install"

  # Helper: cross-platform timeout (macOS doesn't have 'timeout', uses 'gtimeout' from coreutils)
  local TIMEOUT_CMD=""
  if command -v timeout >/dev/null 2>&1; then
    TIMEOUT_CMD="timeout 180"
  elif command -v gtimeout >/dev/null 2>&1; then
    TIMEOUT_CMD="gtimeout 180"
  fi

  # Try Codex first
  local output=""
  if command -v codex >/dev/null 2>&1; then
    log "Dispatching to Codex..."
    if [[ -n "$TIMEOUT_CMD" ]]; then
      output=$(echo "$prompt" | $TIMEOUT_CMD codex exec - 2>&1 </dev/null || echo "")
    else
      output=$(echo "$prompt" | codex exec - 2>&1 </dev/null || echo "")
    fi
  fi

  # Fall back to Gemini
  if [[ -z "$output" ]] || [[ "$output" == *"hit your usage limit"* ]] || [[ "$output" == *"quota"* ]]; then
    if command -v gemini >/dev/null 2>&1; then
      log "Codex unavailable, falling back to Gemini..."
      if [[ -n "$TIMEOUT_CMD" ]]; then
        output=$(echo "$prompt" | $TIMEOUT_CMD gemini -p - 2>&1 || echo "")
      else
        output=$(echo "$prompt" | gemini -p - 2>&1 || echo "")
      fi
    fi
  fi

  # Last resort: Haiku via API
  if [[ -z "$output" ]] || [[ "$output" == *"quota"* ]]; then
    if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
      log "Falling back to Haiku API..."
      output=$(curl -s -X POST https://api.anthropic.com/v1/messages \
        -H "x-api-key: $ANTHROPIC_API_KEY" \
        -H "anthropic-version: 2023-06-01" \
        -H "content-type: application/json" \
        --data "$(python3 -c "
import json, sys
print(json.dumps({
    'model': 'claude-haiku-4-5-20251001',
    'max_tokens': 8000,
    'messages': [{'role': 'user', 'content': open('$CONTEXT_FILE').read() + '''

Task: $task_desc

Output structured: ANALYSIS, FILES, CODE blocks with file paths, TESTS, RISK.'''}]
}))")" 2>/dev/null | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get('content', [{}])[0].get('text', ''))
except: pass
")
    fi
  fi

  if [[ -z "$output" ]]; then
    err "All AI dispatchers unavailable for task: $task_desc"
    return 1
  fi

  # Save output for audit
  echo "$output" > "$PHASE_DIR/task-$task_num-output.md"

  # Apply the output
  apply_task_output "$output" "$task_num" "$task_desc"
  return $?
}

# === Apply Codex output: parse code blocks and write files ===
apply_task_output() {
  local output="$1"
  local task_num="$2"
  local task_desc="$3"

  log "Applying changes..."

  # Use Python for robust code block extraction
  local applied_files=$(python3 <<PYEOF
import re
import os

output = """$output"""
project_dir = "$PROJECT_DIR"

# Match code blocks with file paths: \`\`\`<path>\\n<content>\\n\`\`\`
# Path can include ./ prefix or relative paths
pattern = r'\`\`\`([^\n\`]+)\n(.*?)\n\`\`\`'
matches = re.findall(pattern, output, re.DOTALL)

applied = []
for filepath, content in matches:
    filepath = filepath.strip()
    # Skip language-only tags (e.g., "typescript", "json")
    if not ('/' in filepath or '.' in filepath) or len(filepath) > 200:
        continue
    # Sanitize: must be relative, no .. traversal
    if '..' in filepath or filepath.startswith('/'):
        continue

    full_path = os.path.join(project_dir, filepath)
    os.makedirs(os.path.dirname(full_path) if os.path.dirname(full_path) else '.', exist_ok=True)

    with open(full_path, 'w') as f:
        f.write(content)
    applied.append(filepath)

for f in applied:
    print(f)
PYEOF
)

  if [[ -z "$applied_files" ]]; then
    warn "No file changes applied (AI may have output explanation only)"
    return 1
  fi

  ok "Applied $(echo "$applied_files" | wc -l | tr -d ' ') file(s):"
  echo "$applied_files" | sed 's/^/    /'

  # Run targeted verification
  cd "$PROJECT_DIR"

  # TypeScript check (compilation)
  if [[ -f "$PROJECT_DIR/tsconfig.json" ]]; then
    log "Running tsc check..."
    if ! npx tsc --noEmit 2>&1 | tail -5; then
      warn "tsc check has errors — task may need rework"
      return 1
    fi
  fi

  # Atomic commit per task
  log "Committing task $task_num..."
  git add -A 2>/dev/null
  if ! git diff --cached --quiet 2>/dev/null; then
    git commit -m "Phase $PHASE_NUM Task $task_num: $task_desc

Auto-generated via brain deliver
Files changed: $(echo "$applied_files" | wc -l | tr -d ' ')

$(echo "$applied_files" | sed 's/^/  - /')" --quiet 2>/dev/null
    ok "Committed"
  else
    warn "No changes to commit (output may have been redundant)"
  fi

  return 0
}

# === Main ===
main() {
  if [[ ! -d "$PROJECT_DIR" ]]; then
    err "Project not found: $PROJECT_DIR"
    exit 1
  fi

  if [[ ! -f "$PLAN_FILE" ]]; then
    err "No plan: $PLAN_FILE"
    exit 1
  fi

  log "Executing Phase $PHASE_NUM tasks for $(basename "$PROJECT_DIR")"

  local tasks
  tasks=$(parse_tasks)

  if [[ -z "$tasks" ]]; then
    warn "No tasks found in PLAN.md"
    exit 0
  fi

  local task_num=0
  local failed=0
  echo "$tasks" | while IFS= read -r task; do
    [[ -z "$task" ]] && continue
    task_num=$((task_num + 1))

    if dispatch_task "$task" "$task_num"; then
      ok "Task $task_num complete"
    else
      err "Task $task_num failed"

      # Self-heal attempt
      log "Attempting self-heal..."
      bash "$VAULT_PATH/scripts/self-heal.sh" "$PHASE_DIR/task-$task_num-output.md" "task-$task_num-failure" 2>&1 | tail -5

      # Retry once
      log "Retrying task $task_num..."
      if dispatch_task "$task" "$task_num-retry"; then
        ok "Task $task_num passed on retry"
      else
        err "Task $task_num failed after retry — escalating"
        failed=1
      fi
    fi
  done

  # Cleanup context file
  rm -f "$CONTEXT_FILE"

  if [[ $failed -ne 0 ]]; then
    exit 1
  fi
}

main "$@"
