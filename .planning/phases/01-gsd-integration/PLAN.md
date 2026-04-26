# Phase 1 — GSD Integration: Implementation Plan

**Phase:** 01-gsd-integration
**Status:** in-progress
**Owner:** ark autonomous + user CEO sign-off

## Goal

Make Ark fully aware of GSD's planning structure so it works correctly on GSD-shaped projects (like `strategix-servicedesk`) without breaking legacy Ark-only projects.

## Acceptance Criteria

1. ✅ `ark deliver --phase 1.5` on strategix-servicedesk finds all 9 plan files and 51 tasks
2. ✅ `ark verify` still passes 36/36 after changes
3. ✅ Legacy projects (single PLAN.md) still work
4. ✅ Observer detects regressions automatically (patterns added)
5. ✅ STRUCTURE.md documents the GSD/Ark relationship
6. ✅ Verification suite extends to test GSD-shaped projects

## Implementation Tasks

### Task 1: Audit ALL Ark scripts for GSD-shape assumptions
- [ ] Grep all scripts/*.sh for `phase-${phase_num}` and `PLAN.md` (singular)
- [ ] Document each location in `audit-report.md`
- [ ] Identify which scripts need updating (likely: ark-deliver, ark-team, execute-phase)
- [ ] List which scripts are GSD-shape-agnostic (ark-budget, ark-portfolio, etc.)

### Task 2: Implement shared phase-resolution module
- [ ] Extract `resolve_phase_dir`, `find_plan_files`, `is_gsd_project`, `normalize_phase_num` into `scripts/lib/gsd-shape.sh`
- [ ] Source this lib from any script that needs phase resolution
- [ ] Test the lib in isolation (inline test, not just sourcing)

### Task 3: Update ark-deliver.sh to use shared lib
- [ ] Already partially done — refactor to source lib instead of inline copy
- [ ] When multiple plans found, iterate per-plan (each its own phase-N task batch)
- [ ] Verify: `ark deliver --phase 1.5` against strategix-servicedesk in dry-run mode

### Task 4: Update ark-team.sh to handle multi-plan
- [ ] Currently assumes single PLAN.md — adapt for multi-plan dispatch
- [ ] Each plan file becomes its own architect→engineers→QC→security→PM cycle
- [ ] OR: aggregate all plans into a single team dispatch with sequenced tasks

### Task 5: Update execute-phase.sh
- [ ] Read tasks from ALL plan files in phase dir, not just PLAN.md
- [ ] Maintain task order (01-PLAN.md before 02-PLAN.md, etc.)
- [ ] Dispatch per-task as before, with plan-file context included

### Task 6: Extend ark verify suite
- [ ] Add Tier 7: GSD compatibility tests
  - [ ] resolve_phase_dir against strategix-servicedesk (real project)
  - [ ] find_plan_files returns 9 plans for Phase 1.5
  - [ ] No sibling dir created when GSD shape detected
  - [ ] Legacy single-PLAN.md still resolves correctly
- [ ] Run full suite, expect 40+/40+ pass

### Task 7: Update observer patterns
- [ ] Already added: `gsd-multi-plan-missed`, `gsd-phase-dir-collision`, `empty-plan-dispatched`
- [ ] Add: `phase-dir-creation-without-tasks` (catches if Ark ever writes to a new dir without finding tasks)
- [ ] Verify observer is running and catching test patterns

### Task 8: Update STRUCTURE.md
- [ ] Document GSD layout vs Ark legacy layout
- [ ] Document the hybrid integration model
- [ ] Reference: which Ark commands work with GSD, which need it, which are agnostic

### Task 9: Update employees registry
- [ ] Add `gsd-planner` employee (dispatches to /gsd-plan-phase skill)
- [ ] Add `gsd-verifier` employee (dispatches to /gsd-verify-work skill)
- [ ] Document in employees/README.md (create if missing)

### Task 10: Documentation refresh
- [ ] Update `~/.claude/skills/ark/SKILL.md` to mention GSD integration
- [ ] Update `dashboard/README.md` to show GSD-shaped projects
- [ ] Add example workflow to STRUCTURE.md: "Using Ark with GSD"

## Verification Strategy

After each task, run:
```bash
bash ~/vaults/ark/scripts/ark-verify.sh
```

Expect 36/36 pass through Task 5. After Task 6, expect new tests pass (40+/40+).

End-to-end verification (the "would-have-caught-the-bug" test):
```bash
cd ~/code/strategix-servicedesk
ark deliver --phase 1.5 --dry-run  # should find 9 plans, 51 tasks
```

## Risks

1. **Breaking changes to ark-deliver** — mitigated by keeping legacy code path for projects without `.planning/phases/`
2. **Multi-plan dispatch may overwhelm budget** — mitigated by tier system; if budget hits BLACK, halt
3. **GSD layout may evolve** — observer pattern catches future shape changes

## Dependencies

- GSD skill must remain installed (we depend on `/gsd-plan-phase` for planning)
- Observer daemon must be running (catches regressions)
- Real GSD project required for testing (strategix-servicedesk)

## Out of Scope

- Modifying GSD itself
- Real-time collaboration on plans
- Multi-user GSD/Ark workflows

## Success Signal

Final test:
```bash
cd ~/code/strategix-servicedesk
ark deliver --phase 1.5
```
Should output: phase resolved, 9 plans found, 51 tasks dispatched, team run with valid sign-offs (or correct INFRASTRUCTURE_ERROR if AI quotas dry).

If that works without further band-aiding, Phase 1 is complete.
EOF
