#!/usr/bin/env bash
# Ark error monitor — watch hook output for failures, trigger self-heal
#
# Runs as Stop hook (catches errors after session ends).
# Scans recent logs for error indicators, dispatches self-heal in background.

VAULT_PATH="${ARK_HOME:-$HOME/vaults/ark}"
HEAL_SCRIPT="$VAULT_PATH/scripts/self-heal.sh"

[[ ! -f "$HEAL_SCRIPT" ]] && exit 0

# Look for recent error logs in known locations
ERROR_LOGS=(
  /tmp/ark-sync-*.log
  /tmp/ark-extract-*.log
  /tmp/ark-phase6-*.log
  /tmp/brain-sync-*.log
  /tmp/brain-extract-*.log
  ~/.claude/hooks/ark-hook-debug.log
)

for pattern in "${ERROR_LOGS[@]}"; do
  for log in $pattern; do
    [[ ! -f "$log" ]] && continue
    # Check if log contains error indicators
    if grep -qiE "error|failed|exception|cannot|denied|undefined" "$log" 2>/dev/null; then
      # Dispatch self-heal in background
      (bash "$HEAL_SCRIPT" "$log" "auto-detected" > "/tmp/ark-heal-$$.log" 2>&1 &) 2>/dev/null
    fi
  done
done

exit 0
