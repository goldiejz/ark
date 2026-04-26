# Requirements

| ID | Requirement | Status | Evidence |
|----|-------------|--------|----------|
| R-001 | Single-command interface (`ark`) | done | scripts/ark, 24 commands |
| R-002 | Pluggable employees | done | employees/*.json (14 roles) |
| R-003 | Self-monitoring | done | scripts/ark-observer.sh (daemon running) |
| R-004 | Verification suite | done | scripts/ark-verify.sh (36 checks) |
| R-005 | GSD-aware phase resolution | in-progress | Phase 1 |
| R-006 | Production safety gates | done | ark-promote.sh requires --confirm |
| R-007 | Auto-runtime detection | done | ark-context.sh |
| R-008 | Cost tracking with tier degradation | done | ark-budget.sh (5 tiers) |
| REQ-AOS-01 | `ark deliver` runs to completion under simulated quota+budget exhaustion with zero stdin reads | done | .planning/phases/02-autonomy-policy/02-08-SUMMARY.md |
| REQ-AOS-02 | scripts/ark-policy.sh + cascading config; ark-deliver/ark-team/execute-phase/ark-budget delegate routing | done | 02-01-SUMMARY.md, 02-03-SUMMARY.md, 02-04-SUMMARY.md, 02-05-SUMMARY.md, 02-06-SUMMARY.md, 02-06b-SUMMARY.md |
| REQ-AOS-03 | ESCALATIONS.md queue + `ark escalations` command | done | .planning/phases/02-autonomy-policy/02-02-SUMMARY.md |
| REQ-AOS-04 | policy-decisions.jsonl audit log (schema_version=1, includes decision_id/outcome/correlation_id) | done | .planning/phases/02-autonomy-policy/02-01-SUMMARY.md, STRUCTURE.md |
| REQ-AOS-05 | Tier 8 verify; Tier 1–7 still pass | done | .planning/phases/02-autonomy-policy/02-08-SUMMARY.md |
| REQ-AOS-06 | Observer manual-gate-hit pattern | done | .planning/phases/02-autonomy-policy/02-07-SUMMARY.md |
| REQ-AOS-07 | STRUCTURE.md AOS escalation contract documented | done | .planning/phases/02-autonomy-policy/02-09-SUMMARY.md |
