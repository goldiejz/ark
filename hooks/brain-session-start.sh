#!/usr/bin/env bash
# Brain SessionStart hook — auto-detect and sync brain when entering a project
#
# Behavior:
# - If CWD has .parent-automation/, auto-pull latest vault and refresh snapshot
# - If CWD doesn't have .parent-automation/ but has typical project markers
#   (package.json, .git, src/), suggest 'brain init'
# - Silent if CWD is not a project
#
# This makes brain a fundamental, automatic part of every Claude Code session.

set -euo pipefail

VAULT_PATH="${AUTOMATION_BRAIN_PATH:-$HOME/vaults/automation-brain}"
PROJECT_DIR="$(pwd)"

# Skip if vault doesn't exist
[[ ! -d "$VAULT_PATH" ]] && exit 0

# Skip if we're inside the vault itself
[[ "$PROJECT_DIR" == "$VAULT_PATH"* ]] && exit 0

# Detect project state
HAS_PARENT_AUTOMATION=false
HAS_PROJECT_MARKERS=false

[[ -d "$PROJECT_DIR/.parent-automation" ]] && HAS_PARENT_AUTOMATION=true
([[ -f "$PROJECT_DIR/package.json" ]] || [[ -f "$PROJECT_DIR/Cargo.toml" ]] || [[ -f "$PROJECT_DIR/pyproject.toml" ]] || [[ -f "$PROJECT_DIR/go.mod" ]] || [[ -d "$PROJECT_DIR/.git" ]]) && HAS_PROJECT_MARKERS=true

# Case 1: Has brain integration → silent sync (background, non-blocking)
if [[ "$HAS_PARENT_AUTOMATION" == "true" ]]; then
  # Quick sync in background, don't block session start
  (bash "$VAULT_PATH/scripts/brain-sync.sh" "$PROJECT_DIR" > /tmp/brain-sync-$$.log 2>&1 &) 2>/dev/null

  # Print status to Claude (this becomes context)
  SNAPSHOT_MANIFEST="$PROJECT_DIR/.parent-automation/brain-snapshot/SNAPSHOT-MANIFEST.json"
  if [[ -f "$SNAPSHOT_MANIFEST" ]]; then
    LESSONS=$(grep -o '"lessons":[ ]*[0-9]*' "$SNAPSHOT_MANIFEST" | head -1 | grep -o '[0-9]*')
    DECISIONS=0
    if [[ -f "$PROJECT_DIR/.planning/bootstrap-decisions.jsonl" ]]; then
      DECISIONS=$(wc -l < "$PROJECT_DIR/.planning/bootstrap-decisions.jsonl" | tr -d ' ')
    fi
    cat <<EOF
=== BRAIN ACTIVE ===
Project: $(basename "$PROJECT_DIR")
Snapshot: $LESSONS lessons available
Decisions logged: $DECISIONS
Vault: $VAULT_PATH
Sync: in progress (background)
Available: /brain status, /brain bootstrap, /brain insights, /brain scaffold
====================
EOF
  fi
  exit 0
fi

# Case 2: Looks like a project but no brain → suggest init
if [[ "$HAS_PROJECT_MARKERS" == "true" ]]; then
  cat <<EOF
=== BRAIN AVAILABLE ===
This project has no .parent-automation/ — brain not active.
To activate: /brain init
Benefits: 70% token reduction, cross-project lessons, decision logging
======================
EOF
  exit 0
fi

# Case 3: Not a project — silent
exit 0
