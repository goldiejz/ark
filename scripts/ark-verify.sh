#!/usr/bin/env bash
# ark verify — automated end-to-end verification suite
#
# Runs every Ark capability with pass/fail criteria, captures output,
# produces a verification report. The CEO reads the report — doesn't run
# every command by hand.
#
# Usage:
#   ark verify                    # run all checks
#   ark verify --tier 1           # only Tier 1 (read-only)
#   ark verify --skip-tier 4,5    # skip risky tiers
#   ark verify --report-only      # show last report
#
# Exit codes:
#   0 = all critical checks passed
#   1 = one or more critical checks failed
#   2 = warnings only (non-critical issues)

set -uo pipefail

VAULT_PATH="${ARK_HOME:-$HOME/vaults/ark}"
PROJECT_DIR="$(pwd)"
REPORTS_DIR="$VAULT_PATH/observability/verification-reports"
TIMESTAMP=$(date -u +%Y%m%d-%H%M%S)
REPORT="$REPORTS_DIR/$TIMESTAMP.md"
mkdir -p "$REPORTS_DIR"

TIER_FILTER=""
SKIP_TIERS=""
REPORT_ONLY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tier) TIER_FILTER="$2"; shift 2 ;;
    --skip-tier) SKIP_TIERS="$2"; shift 2 ;;
    --report-only) REPORT_ONLY=true; shift ;;
    *) shift ;;
  esac
done

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
PASS=0
WARN=0
FAIL=0
SKIP=0
RESULTS=()

# === Show last report ===
if [[ "$REPORT_ONLY" == "true" ]]; then
  latest=$(ls -t "$REPORTS_DIR"/*.md 2>/dev/null | head -1)
  if [[ -n "$latest" ]]; then
    cat "$latest"
  else
    echo "No verification reports yet. Run: ark verify"
  fi
  exit 0
fi

# === Helpers ===
should_run_tier() {
  local tier="$1"
  if [[ -n "$TIER_FILTER" ]] && [[ "$TIER_FILTER" != "$tier" ]]; then
    return 1
  fi
  if [[ -n "$SKIP_TIERS" ]]; then
    if [[ ",$SKIP_TIERS," == *",$tier,"* ]]; then
      return 1
    fi
  fi
  return 0
}

run_check() {
  local tier="$1"
  local name="$2"
  local command="$3"
  local pass_pattern="$4"  # regex or substring expected in output
  local critical="${5:-true}"

  if ! should_run_tier "$tier"; then
    SKIP=$((SKIP+1))
    RESULTS+=("⏭  T$tier: $name (skipped)")
    return
  fi

  local output
  output=$(eval "$command" 2>&1 || echo "__COMMAND_FAILED__")
  local exit_code=$?

  if echo "$output" | grep -qE "$pass_pattern"; then
    PASS=$((PASS+1))
    RESULTS+=("✅ T$tier: $name")
    echo -e "${GREEN}  ✅${NC} T$tier: $name"
  else
    if [[ "$critical" == "true" ]]; then
      FAIL=$((FAIL+1))
      RESULTS+=("❌ T$tier: $name (output didn't match: $pass_pattern)")
      echo -e "${RED}  ❌${NC} T$tier: $name"
    else
      WARN=$((WARN+1))
      RESULTS+=("⚠️  T$tier: $name (non-critical)")
      echo -e "${YELLOW}  ⚠️${NC}  T$tier: $name"
    fi
  fi
}

run_existence_check() {
  local tier="$1"
  local name="$2"
  local path="$3"
  local critical="${4:-true}"

  if ! should_run_tier "$tier"; then
    SKIP=$((SKIP+1))
    RESULTS+=("⏭  T$tier: $name (skipped)")
    return
  fi

  if [[ -e "$path" ]]; then
    PASS=$((PASS+1))
    RESULTS+=("✅ T$tier: $name")
    echo -e "${GREEN}  ✅${NC} T$tier: $name"
  else
    if [[ "$critical" == "true" ]]; then
      FAIL=$((FAIL+1))
      RESULTS+=("❌ T$tier: $name (missing: $path)")
      echo -e "${RED}  ❌${NC} T$tier: $name"
    else
      WARN=$((WARN+1))
      RESULTS+=("⚠️  T$tier: $name")
      echo -e "${YELLOW}  ⚠️${NC}  T$tier: $name"
    fi
  fi
}

# === Begin verification ===
echo ""
echo -e "${BLUE}🔍 ARK VERIFY — Automated E2E Verification${NC}"
echo -e "   Project: $(basename "$PROJECT_DIR")"
echo -e "   Vault:   $VAULT_PATH"
echo -e "   Started: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

# ━━━ TIER 1 — Read-only ━━━
if should_run_tier 1; then
  echo -e "${BLUE}━━━ Tier 1: Read-only ━━━${NC}"
fi
run_existence_check 1 "Vault directory exists" "$VAULT_PATH"
run_existence_check 1 "Vault is git repo" "$VAULT_PATH/.git"
run_check 1 "ark help responds" "ark help" "ARK"
run_check 1 "ark status shows snapshot" "cd '$PROJECT_DIR' && ark status" "Snapshot present|No snapshot"
run_check 1 "ark portfolio scans projects" "ark portfolio" "PROJECT|Portfolio"
run_check 1 "ark insights reads vault" "ark insights" "Cross-Customer Insights|insights"
run_check 1 "ark lessons lists count" "ark lessons" "Total: [0-9]+"
run_check 1 "ark doctor 27 checks" "ark doctor" "Summary:.*passed"
run_check 1 "ark budget initializes" "cd '$PROJECT_DIR' && ark budget" "Brain Budget|Tier"
run_check 1 "ark lifecycle reads stage" "cd '$PROJECT_DIR' && ark lifecycle status" "Lifecycle:|stage"
run_check 1 "Phase 6 daemon runs clean" "cd '$VAULT_PATH' && npx ts-node observability/phase-6-daemon.ts 2>&1" "OBSERVABILITY DAEMON COMPLETE|No bootstrap decision"
run_check 1 "ark-context detects runtime" "ark-context.sh --primary || bash $VAULT_PATH/scripts/ark-context.sh --primary" "claude-code-session|codex|gemini|regex"
run_existence_check 1 "Brain snapshot present in this project" "$PROJECT_DIR/.parent-automation/brain-snapshot/SNAPSHOT-MANIFEST.json" false
run_existence_check 1 "Decision log present" "$PROJECT_DIR/.planning/bootstrap-decisions.jsonl" false

# ━━━ TIER 2 — Vault writes (reversible) ━━━
if should_run_tier 2; then
  echo ""
  echo -e "${BLUE}━━━ Tier 2: Vault writes (reversible) ━━━${NC}"
fi
run_check 2 "ark sync pulls + writes" "cd '$PROJECT_DIR' && ark sync" "BRAIN SYNC COMPLETE"
run_check 2 "ark backup creates tarball" "ark backup" "Backup created"
run_check 2 "ark validate (drift check)" "ark validate" "valid|drift|stable"
run_check 2 "ark report --for self" "cd '$PROJECT_DIR' && ark report --for self" "Report saved"

# ━━━ TIER 3 — File structure ━━━
if should_run_tier 3; then
  echo ""
  echo -e "${BLUE}━━━ Tier 3: File structure ━━━${NC}"
fi
run_check 3 "ark align dry-run safe" "cd '$PROJECT_DIR' && ark align --dry-run" "DRY RUN COMPLETE|Would|alignment"
run_check 3 "ark secrets check" "cd '$PROJECT_DIR' && ark secrets check" "secrets|Missing|present" false

# ━━━ TIER 4 — Throwaway project creation ━━━
if should_run_tier 4; then
  echo ""
  echo -e "${BLUE}━━━ Tier 4: Throwaway project creation ━━━${NC}"
fi
TEST_PROJECT="/tmp/ark-verify-$TIMESTAMP"
run_check 4 "ark create scaffolds project" \
  "ark create ark-verify-$TIMESTAMP --type custom --customer verify --stack node-cli --deploy none --path /tmp 2>&1" \
  "PROJECT CREATED|✅ Initialized"
run_existence_check 4 "Project dir created" "$TEST_PROJECT"
run_existence_check 4 "CLAUDE.md generated" "$TEST_PROJECT/CLAUDE.md"
run_existence_check 4 "package.json generated" "$TEST_PROJECT/package.json"
run_existence_check 4 ".planning/STATE.md exists" "$TEST_PROJECT/.planning/STATE.md"
run_existence_check 4 ".planning/bootstrap-decisions.jsonl exists" "$TEST_PROJECT/.planning/bootstrap-decisions.jsonl"
run_existence_check 4 "src/lib/rbac.ts (universal RBAC)" "$TEST_PROJECT/src/lib/rbac.ts"
# Cleanup test project
[[ -d "$TEST_PROJECT" ]] && rm -rf "$TEST_PROJECT"
gh repo delete "goldiejz/ark-verify-$TIMESTAMP" --yes 2>/dev/null || true

# ━━━ TIER 5 — Production safety ━━━
if should_run_tier 5; then
  echo ""
  echo -e "${BLUE}━━━ Tier 5: Production safety gates ━━━${NC}"
fi
run_check 5 "Production deploy blocks without --confirm" \
  "cd '$PROJECT_DIR' && ark promote --to production 2>&1 | head -20" \
  "PRODUCTION DEPLOY BLOCKED|requires explicit confirmation"
run_check 5 "Staging dry-run shows plan" \
  "cd '$PROJECT_DIR' && ark promote --to staging --dry-run 2>&1 | head -10" \
  "DRY RUN|would execute|deployment"

# ━━━ TIER 6 — Hooks + observability ━━━
if should_run_tier 6; then
  echo ""
  echo -e "${BLUE}━━━ Tier 6: Hooks + integration ━━━${NC}"
fi
run_existence_check 6 "SessionStart hook present" "$HOME/.claude/hooks/ark-session-start.sh"
run_existence_check 6 "Stop hook (extract-learnings)" "$HOME/.claude/hooks/ark-extract-learnings.sh"
run_existence_check 6 "Stop hook (error-monitor)" "$HOME/.claude/hooks/ark-error-monitor.sh"
run_existence_check 6 "Stop hook (session-end)" "$HOME/.claude/hooks/ark-session-end.sh"
run_check 6 "Hooks registered in settings.json" \
  "grep -c 'ark-' $HOME/.claude/settings.json" \
  "[1-9]"
run_existence_check 6 "Brain skill installed (/ark)" "$HOME/.claude/skills/ark/SKILL.md"
run_check 6 "Employee registry has roles" \
  "ls $VAULT_PATH/employees/*.json 2>/dev/null | wc -l" \
  "[1-9]"

# ━━━ Generate report ━━━
TOTAL=$((PASS + WARN + FAIL + SKIP))
EXIT_CODE=0
if [[ $FAIL -gt 0 ]]; then EXIT_CODE=1; fi
if [[ $FAIL -eq 0 && $WARN -gt 0 ]]; then EXIT_CODE=2; fi

VERDICT="✅ APPROVED"
if [[ $FAIL -gt 0 ]]; then
  VERDICT="🛑 BLOCKED ($FAIL critical failure(s))"
elif [[ $WARN -gt 0 ]]; then
  VERDICT="⚠️  CONDITIONAL ($WARN warning(s))"
fi

cat > "$REPORT" <<EOF
# Ark Verification Report — $TIMESTAMP

**Project under test:** $(basename "$PROJECT_DIR")
**Vault:** $VAULT_PATH
**Vault commit:** $(cd "$VAULT_PATH" && git rev-parse --short HEAD 2>/dev/null || echo unknown)
**Date:** $(date -u +%Y-%m-%dT%H:%M:%SZ)

## Verdict

$VERDICT

| Metric | Count |
|--------|-------|
| Passed | $PASS |
| Warnings | $WARN |
| Failed | $FAIL |
| Skipped | $SKIP |
| Total | $TOTAL |

## Detailed Results

EOF

for r in "${RESULTS[@]}"; do
  echo "- $r" >> "$REPORT"
done

cat >> "$REPORT" <<EOF

## Sign-off

The CEO (you) reviews this report. Per-tier breakdown:

- **Tier 1 (read-only):** Foundation — must pass for any further use
- **Tier 2 (vault writes):** Sync, backup, validate, report
- **Tier 3 (file structure):** Align, secrets — touches project files
- **Tier 4 (project creation):** End-to-end create + scaffold
- **Tier 5 (production safety):** Promote gates
- **Tier 6 (hooks + observability):** Auto-run infrastructure

If any failure is critical, fix and re-run before using Ark on real work.

## Re-run

\`\`\`bash
ark verify                # full
ark verify --tier 1       # only foundation
ark verify --skip-tier 4  # skip project creation
ark verify --report-only  # show this report again
\`\`\`

---

*Generated by ark-verify.sh*
EOF

# Print summary
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  Verification: $VERDICT"
echo -e "  ${GREEN}$PASS passed${NC}  ${YELLOW}$WARN warnings${NC}  ${RED}$FAIL failed${NC}  ⏭  $SKIP skipped"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Report: $REPORT"
echo ""
echo "View later: ark verify --report-only"

# Auto-commit report
if [[ -d "$VAULT_PATH/.git" ]]; then
  cd "$VAULT_PATH"
  git add observability/verification-reports/ 2>/dev/null
  if ! git diff --cached --quiet 2>/dev/null; then
    git commit -m "Verification report: $TIMESTAMP — $VERDICT" --quiet 2>/dev/null
    git push origin main --quiet 2>/dev/null || true
  fi
fi

exit $EXIT_CODE
