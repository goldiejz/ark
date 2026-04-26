# Phase 1 — GSD Integration: Context

## Why this phase exists

Ark and GSD are complementary systems that should work together seamlessly:
- **GSD** handles planning, requirements, phase decomposition (the "what" and "how to plan")
- **Ark** handles agent dispatch, autonomous execution, governance (the "who executes" and "how to ship")

Real-world test on `strategix-servicedesk` (a GSD project) revealed Ark's planning logic doesn't recognize GSD's directory shape. This causes Ark to write empty plans into sibling directories and dispatch no-op team runs.

## Discovered defects (root causes)

### Defect 1: Phase directory shape blindness
- **GSD layout:** `.planning/phases/01.5-parity-polish-2-3-weeks-after-phase-1-close/`
- **Ark assumed:** `.planning/phase-1.5/`
- **Symptom:** Ark created sibling dir, GSD plans invisible

### Defect 2: Multi-plan-per-phase blindness
- **GSD reality:** 9 plan files per phase (`01.5-01-PLAN.md` through `01.5-09-PLAN.md`)
- **Ark assumed:** single `PLAN.md` per phase
- **Symptom:** "0 tasks to execute" when 51 real tasks existed

### Defect 3: No GSD detection
- Ark didn't check whether project uses GSD before applying its own conventions
- Should auto-detect and either delegate or adapt

### Defect 4: PM sign-off mistook quota errors for review verdicts
- Already partially fixed (BLOCKED → INFRASTRUCTURE_ERROR distinction)
- Needs deeper integration: when GSD-shaped plan, use GSD's verification model

## Stakeholders

- **User (CEO):** asked for proper GSD integration after spotting band-aid pattern
- **Ark observer:** will monitor for regressions
- **strategix-servicedesk:** real test target

## Constraints

- **No breaking changes** to existing Ark verification (`ark verify` must stay 36/36)
- **Backward compat:** legacy ark-only projects (`.planning/phase-N/PLAN.md`) must still work
- **Test before claim:** every fix verified against real `strategix-servicedesk` layout
- **Observer-coverable:** new bug classes added as patterns so they auto-detect

## Decision: Delegate or Reimplement?

**Recommendation: Adapt, don't delegate.** Reasoning:
- GSD's `/gsd:execute-phase` is an interactive Claude Code command, hard to invoke from shell
- Ark's value is autonomous shell execution + observability hooks
- Better to make Ark's `ark deliver` GSD-shape-aware than to require Claude Code session for execution
- Where GSD's commands shine (planning, discussion, audit), keep using them via skill
- Where Ark's commands shine (autonomous dispatch, monitoring), enhance them

Hybrid model:
- `/gsd-plan-phase` → produces PLAN.md (this is what we're doing now)
- `ark deliver --phase N` → reads GSD-shape plans, dispatches autonomously
- `/gsd-verify-work` → conversational UAT
- `ark promote` → safe deployment with hooks
EOF
