#!/usr/bin/env bash
# Ark Stop hook — auto-extract learnings from completed session
#
# What it does:
# 1. On session end, dispatches to AI cascade for lesson extraction
# 2. Writes structured lessons to vault auto-captured/
# 3. Triggers Phase 6 to detect patterns
# 4. All async, non-blocking — session ends immediately
#
# Token cost: ~0 (free tier preferred) or regex fallback
# Result: Brain accumulates lessons without human intervention

VAULT_PATH="${ARK_HOME:-$HOME/vaults/ark}"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
SESSION_ID="${CLAUDE_IDE_SESSION_ID:-unknown}"

# Skip if vault doesn't exist
[[ ! -d "$VAULT_PATH" ]] && exit 0
# Skip if inside vault
[[ "$PROJECT_DIR" == "$VAULT_PATH"* ]] && exit 0

# Find session transcript (Claude stores in ~/.claude/projects/<dir>/<session-id>.jsonl)
PROJECT_HASH=$(echo "$PROJECT_DIR" | sed 's|/|-|g')
TRANSCRIPT_DIR="$HOME/.claude/projects/$PROJECT_HASH"
TRANSCRIPT=""
if [[ -d "$TRANSCRIPT_DIR" ]]; then
  TRANSCRIPT=$(find "$TRANSCRIPT_DIR" -name "*.jsonl" -type f 2>/dev/null | xargs ls -t 2>/dev/null | head -1)
fi

# Skip if no transcript
[[ -z "$TRANSCRIPT" || ! -f "$TRANSCRIPT" ]] && exit 0

# Dispatch the extraction in background — never block session end
(
  EXTRACT_SCRIPT="$VAULT_PATH/scripts/extract-learnings.sh"
  if [[ -f "$EXTRACT_SCRIPT" ]]; then
    bash "$EXTRACT_SCRIPT" "$TRANSCRIPT" "$PROJECT_DIR" "$SESSION_ID" \
      > "/tmp/ark-extract-$SESSION_ID.log" 2>&1
  fi
) &
disown 2>/dev/null || true

exit 0
