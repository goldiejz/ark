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
