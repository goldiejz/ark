#!/usr/bin/env bash
# brain-pm-signoff — aggregate team reports and gate sign-off
#
# Pure aggregator — no AI calls. Reads YAML/markdown verdicts from team
# members and produces final PM decision + CEO report.

set -uo pipefail

PROJECT_DIR="${1:?project dir required}"
PHASE_NUM="${2:?phase number required}"

PHASE_DIR="$PROJECT_DIR/.planning/phase-$PHASE_NUM"
TEAM_DIR="$PHASE_DIR/team"

# Helper: detect if a team artifact is a quota/error blob (not real verdict)
is_error_blob() {
  local f="$1"
  [[ ! -f "$f" ]] && return 0
  # Quota / network / dispatcher errors masquerading as content
  if grep -qiE "QUOTA_EXHAUSTED|TerminalQuotaError|hit your usage limit|capacity.*reset|reset in [0-9]+h|API key.*missing|No prompt provided" "$f" 2>/dev/null; then
    return 0
  fi
  # File too small to be a real verdict
  [[ $(wc -c < "$f" 2>/dev/null | tr -d ' ') -lt 100 ]] && return 0
  return 1
}

# Determine each role's verdict — distinguish "ran but error" from "approved"
ARCH_STATUS="UNKNOWN"
if [[ -f "$TEAM_DIR/architect-design.md" ]]; then
  if is_error_blob "$TEAM_DIR/architect-design.md"; then
    ARCH_STATUS="DISPATCH_ERROR"
  else
    ARCH_STATUS="DESIGNED"
  fi
fi

QC_STATUS="UNKNOWN"
if [[ -f "$TEAM_DIR/qc-review.md" ]]; then
  if is_error_blob "$TEAM_DIR/qc-review.md"; then
    QC_STATUS="DISPATCH_ERROR"
  elif grep -qiE "verdict:\s*APPROVE|^APPROVE$|^Approved" "$TEAM_DIR/qc-review.md"; then
    QC_STATUS="APPROVED"
  elif grep -qiE "verdict:\s*REJECT|^REJECT$|^Rejected" "$TEAM_DIR/qc-review.md"; then
    QC_STATUS="REJECTED"
  else
    QC_STATUS="CHANGES_REQUESTED"
  fi
fi

SEC_STATUS="UNKNOWN"
if [[ -f "$TEAM_DIR/security-audit.md" ]]; then
  if is_error_blob "$TEAM_DIR/security-audit.md"; then
    SEC_STATUS="DISPATCH_ERROR"
  elif grep -qiE "verdict:\s*APPROVE|no.*critical|no.*high" "$TEAM_DIR/security-audit.md"; then
    SEC_STATUS="APPROVED"
  else
    SEC_STATUS="REJECTED"
  fi
fi

QA_STATUS="UNKNOWN"
if [[ -f "$TEAM_DIR/qa-tests.log" ]]; then
  if is_error_blob "$TEAM_DIR/qa-tests.log"; then
    QA_STATUS="DISPATCH_ERROR"
  elif grep -qE "passed|all tests pass|0 failed" "$TEAM_DIR/qa-tests.log"; then
    QA_STATUS="APPROVED"
  elif grep -qE "no test files|N/A" "$TEAM_DIR/qa-tests.log"; then
    QA_STATUS="N/A"
  else
    QA_STATUS="REJECTED"
  fi
fi

ENG_STATUS="UNKNOWN"
if [[ -f "$TEAM_DIR/engineers-execution.log" ]]; then
  if grep -qE "Task .* complete|claude-code-session.*handoff" "$TEAM_DIR/engineers-execution.log"; then
    ENG_STATUS="COMPLETED"
  elif grep -qE "No tasks found|no actionable tasks" "$TEAM_DIR/engineers-execution.log"; then
    ENG_STATUS="NO_TASKS"
  elif grep -qE "QUOTA_EXHAUSTED|hit your usage limit|All AI dispatchers unavailable" "$TEAM_DIR/engineers-execution.log"; then
    ENG_STATUS="DISPATCH_ERROR"
  fi
fi

# PM verdict — distinguish 4 outcomes:
#   APPROVED          → all roles approved real work
#   REJECTED          → real review found issues
#   INFRASTRUCTURE    → AI quotas exhausted / dispatch errors (NOT a real rejection)
#   NO_TASKS          → phase has nothing to do (auto-skip, not a failure)
PM_VERDICT="REJECTED"

# Count infrastructure errors
INFRA_ERRORS=0
[[ "$ARCH_STATUS" == "DISPATCH_ERROR" ]] && INFRA_ERRORS=$((INFRA_ERRORS+1))
[[ "$QC_STATUS" == "DISPATCH_ERROR" ]] && INFRA_ERRORS=$((INFRA_ERRORS+1))
[[ "$SEC_STATUS" == "DISPATCH_ERROR" ]] && INFRA_ERRORS=$((INFRA_ERRORS+1))
[[ "$QA_STATUS" == "DISPATCH_ERROR" ]] && INFRA_ERRORS=$((INFRA_ERRORS+1))
[[ "$ENG_STATUS" == "DISPATCH_ERROR" ]] && INFRA_ERRORS=$((INFRA_ERRORS+1))

if [[ "$ENG_STATUS" == "NO_TASKS" ]]; then
  PM_VERDICT="NO_TASKS"
elif [[ $INFRA_ERRORS -ge 2 ]]; then
  # 2+ team members couldn't even run = infrastructure failure, not a review verdict
  PM_VERDICT="INFRASTRUCTURE_ERROR"
elif [[ "$ENG_STATUS" == "COMPLETED" ]] && \
     [[ "$QC_STATUS" == "APPROVED" ]] && \
     [[ "$SEC_STATUS" == "APPROVED" ]] && \
     ([[ "$QA_STATUS" == "APPROVED" ]] || [[ "$QA_STATUS" == "N/A" ]]); then
  PM_VERDICT="APPROVED"
fi

# Generate PM sign-off
cat > "$TEAM_DIR/pm-signoff.md" <<EOF
# Phase $PHASE_NUM — PM Sign-off

**Date:** $(date -u +%Y-%m-%dT%H:%M:%SZ)
**Verdict:** $PM_VERDICT

## Team Reports

| Role | Status | Source |
|------|--------|--------|
| Architect | $ARCH_STATUS | team/architect-design.md |
| Engineers | $ENG_STATUS | team/engineers-execution.log |
| QC | $QC_STATUS | team/qc-review.md |
| QA | $QA_STATUS | team/qa-tests.log |
| Security | $SEC_STATUS | team/security-audit.md |

## Decision

EOF

if [[ "$PM_VERDICT" == "APPROVED" ]]; then
  echo "✅ All team members approve. Phase signed off." >> "$TEAM_DIR/pm-signoff.md"
elif [[ "$PM_VERDICT" == "NO_TASKS" ]]; then
  cat >> "$TEAM_DIR/pm-signoff.md" <<EOF
ℹ️  Phase has no actionable tasks remaining. Auto-skipped.

If this phase should have work, update PLAN.md or ROADMAP.md.
EOF
elif [[ "$PM_VERDICT" == "INFRASTRUCTURE_ERROR" ]]; then
  cat >> "$TEAM_DIR/pm-signoff.md" <<EOF
⚠️  INFRASTRUCTURE ERROR — this is NOT a code review rejection.

Multiple team members ($INFRA_ERRORS) could not even run. Their artifacts
contain dispatcher errors (quota exhausted, no AI available, etc.), not
real verdicts on the work.

This phase is not blocked due to bad code — it's blocked because the
review pipeline itself failed. Resolve infrastructure (AI quotas, API keys,
network) and re-run.

Affected roles:
EOF
  [[ "$ARCH_STATUS" == "DISPATCH_ERROR" ]] && echo "- Architect: dispatcher error" >> "$TEAM_DIR/pm-signoff.md"
  [[ "$QC_STATUS" == "DISPATCH_ERROR" ]] && echo "- QC: dispatcher error" >> "$TEAM_DIR/pm-signoff.md"
  [[ "$SEC_STATUS" == "DISPATCH_ERROR" ]] && echo "- Security: dispatcher error" >> "$TEAM_DIR/pm-signoff.md"
  [[ "$QA_STATUS" == "DISPATCH_ERROR" ]] && echo "- QA: dispatcher error" >> "$TEAM_DIR/pm-signoff.md"
  [[ "$ENG_STATUS" == "DISPATCH_ERROR" ]] && echo "- Engineers: dispatcher error" >> "$TEAM_DIR/pm-signoff.md"
else
  cat >> "$TEAM_DIR/pm-signoff.md" <<EOF
🛑 Phase blocked. Required actions:

EOF
  [[ "$ENG_STATUS" != "COMPLETED" ]] && [[ "$ENG_STATUS" != "DISPATCH_ERROR" ]] && echo "- Engineering not complete — see engineers-execution.log" >> "$TEAM_DIR/pm-signoff.md"
  [[ "$QC_STATUS" == "REJECTED" || "$QC_STATUS" == "CHANGES_REQUESTED" ]] && echo "- Address QC issues — see qc-review.md" >> "$TEAM_DIR/pm-signoff.md"
  [[ "$SEC_STATUS" == "REJECTED" ]] && echo "- Resolve security findings — see security-audit.md" >> "$TEAM_DIR/pm-signoff.md"
  [[ "$QA_STATUS" == "REJECTED" ]] && echo "- Fix failing tests — see qa-tests.log" >> "$TEAM_DIR/pm-signoff.md"
fi

# Generate CEO report
cat > "$PROJECT_DIR/.planning/phase-$PHASE_NUM-ceo-report.md" <<EOF
# CEO Report — Phase $PHASE_NUM

**Date:** $(date -u +%Y-%m-%dT%H:%M:%SZ)
**Project:** $(basename "$PROJECT_DIR")
**Status:** $(case "$PM_VERDICT" in
  APPROVED) echo "✅ DELIVERED" ;;
  NO_TASKS) echo "ℹ️  NO TASKS (skipped)" ;;
  INFRASTRUCTURE_ERROR) echo "⚠️  INFRASTRUCTURE ERROR (AI quotas/dispatchers unavailable — not a real review block)" ;;
  *) echo "🛑 BLOCKED" ;;
esac)

## Team Sign-offs
| Role | Status |
|------|--------|
| Architect | $ARCH_STATUS |
| Engineers | $ENG_STATUS |
| QC | $QC_STATUS |
| QA | $QA_STATUS |
| Security | $SEC_STATUS |
| PM | $PM_VERDICT |

## Next Step
$([ "$PM_VERDICT" == "APPROVED" ] && echo "Run \`ark deliver --phase $((PHASE_NUM + 1))\`" || echo "Address blockers in team/pm-signoff.md, then retry")

## Detailed Reports
.planning/phase-$PHASE_NUM/team/*.md
EOF

echo "✅ PM sign-off: $TEAM_DIR/pm-signoff.md"
echo "✅ CEO report: .planning/phase-$PHASE_NUM-ceo-report.md"
echo "Verdict: $PM_VERDICT"

# Exit codes:
#   0 = APPROVED or NO_TASKS (success / nothing to do)
#   1 = real review rejection (engineer/QC/QA/security said no)
#   3 = INFRASTRUCTURE_ERROR (AI dispatchers failed, not a review block)
case "$PM_VERDICT" in
  APPROVED|NO_TASKS) exit 0 ;;
  INFRASTRUCTURE_ERROR) exit 3 ;;
  *) exit 1 ;;
esac
