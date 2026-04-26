---
phase: 05-portfolio-autonomy
plan: 07
subsystem: phase-5-doc-truth-up
tags: [aos, phase-5, wave-5, doc-only, requirements, state, roadmap, structure, skill, exit-close]
requirements:
  - REQ-AOS-23
  - REQ-AOS-24
  - REQ-AOS-25
  - REQ-AOS-26
  - REQ-AOS-27
  - REQ-AOS-28
  - REQ-AOS-29
  - REQ-AOS-30
dependency_graph:
  requires:
    - .planning/phases/05-portfolio-autonomy/05-06-SUMMARY.md (Tier 11 16/16 + Tier 7-10 retention numbers)
    - All Phase 5 plan SUMMARY files (05-01..05-06)
  provides:
    - "REQ-AOS-23..30 minted in REQUIREMENTS.md"
    - ".planning/STATE.md frontmatter + body reflect Phase 5 complete"
    - ".planning/ROADMAP.md Phase 5 ticked"
    - "STRUCTURE.md AOS Portfolio Autonomy Contract section"
    - "~/.claude/skills/ark/SKILL.md Phase 5 posture"
  affects:
    - "Phase 6 (Cross-Customer Learning Autonomy) — reads class:portfolio audit rows"
tech-stack:
  added: []
  patterns:
    - "Mirror Phase 4 doc-truth-up shape (REQ row format, STATE plan-table, contract structure)"
    - "STRUCTURE.md is hardlinked at /Users/jongoldberg/vaults/automation-brain/STRUCTURE.md and /Users/jongoldberg/vaults/ark/STRUCTURE.md (same inode 44762697); single edit covers both"
key-files:
  created:
    - .planning/phases/05-portfolio-autonomy/05-07-SUMMARY.md
  modified:
    - .planning/REQUIREMENTS.md
    - .planning/STATE.md
    - .planning/ROADMAP.md
    - STRUCTURE.md
    - ~/.claude/skills/ark/SKILL.md (outside git; not committed in this commit)
decisions:
  - "Set STATE.md progress.percent to 71 per plan instructions (5/7 phases complete). Phase 1 remains in-progress (3 of 10 task checkboxes ticked) but is treated as a completed phase for AOS-track counting since Phases 2-5 depend on it being usable; the plan-level total_plans=41 still reflects 7 Phase 5 plans on top of the prior 34."
  - "STATE.md tail section renamed from 'Phase 5+ — Future' to 'Phase 6+ — Future' with explicit Phase 6 pointer (Cross-Customer Learning Autonomy + Tier 12 verify)."
  - "STRUCTURE.md contract section placed after the Phase 4 Bootstrap Autonomy Contract, mirroring the existing chronological contract series (Escalation → Self-Improving Self-Heal → Bootstrap → Portfolio)."
  - "CEO directive contract documented as a *score boost (+5)*, NOT a budget override — matches observed Tier 11 run2 behavior. Future contract change can revisit; this plan documents current truth."
  - "SKILL.md lives at ~/.claude/skills/ark/SKILL.md, not in either vault. Updated in place; no commit (path is outside any git repo). REQ-AOS-23..30 acceptance is met by the SKILL.md update being best-effort per plan."
metrics:
  duration: ~12min
  tasks_completed: 5
  completed_date: 2026-04-26
---

# Phase 5 Plan 05-07: Phase 5 doc truth-up + close — Summary

**One-liner:** Closed Phase 5 in the planning truth files — minted REQ-AOS-23..30 in REQUIREMENTS.md, marked STATE.md `completed_phases: 5`, ticked ROADMAP.md Phase 5 checkboxes, appended the AOS Portfolio Autonomy Contract to STRUCTURE.md, and updated `~/.claude/skills/ark/SKILL.md` with Phase 5 posture.

## What was built

### Task 1 — REQUIREMENTS.md: REQ-AOS-23..30

Appended 8 rows to the table after REQ-AOS-22, mirroring the Phase 4 row format (`| ID | Requirement | Status | Evidence |`). All 8 marked `done` with concrete evidence references (script paths, test counts, plan SUMMARY paths).

| ID | Subject |
|----|---------|
| REQ-AOS-23 | ark-portfolio-decide.sh exists; sourceable; 40/40 self-test |
| REQ-AOS-24 | `ark deliver` no-args picks highest-priority project; zero prompts |
| REQ-AOS-25 | Decision audit-logged via `_policy_log "portfolio" SELECTED ...` |
| REQ-AOS-26 | Per-customer monthly budget caps honored; over-cap → DEFERRED |
| REQ-AOS-27 | CEO directive `## Next Priority` adds +5 score boost |
| REQ-AOS-28 | `ark deliver --phase N` and in-project invocations unchanged |
| REQ-AOS-29 | Tier 11 verify (synthetic 3-project / 2-customer fixture, 16/16) |
| REQ-AOS-30 | Tier 1–10 still pass post-Phase-5 |

### Task 2 — STATE.md: Phase 5 close

Frontmatter:
- `current_phase: "Phase 5 (AOS: Portfolio Autonomy)"`
- `status: complete`
- `last_updated: "2026-04-26T18:30:00Z"`
- `progress.completed_phases: 5`
- `progress.total_plans: 41`
- `progress.completed_plans: 41`
- `progress.percent: 71`

Body:
- Top header lines updated to match (Current Phase / Status / Last updated)
- New `## Phase 5 — AOS: Portfolio Autonomy (complete)` section appended with goal statement, exit-gate evidence (Tier 11 16/16; Tier 7/8/9/10 retained at 14/25/20/22), and a 7-row plan-outcome table (05-01..05-07)
- Trailing future-pointer rewritten to `## Phase 6+ — Future` referencing Phase 6 (Cross-Customer Learning Autonomy + Tier 12 verify)

### Task 3 — ROADMAP.md: Phase 5 ticked

Inside `### Phase 5 — AOS: Portfolio Autonomy`:
- Heading suffixed with `(complete)`
- All 6 `- [ ]` checkboxes converted to `- [x]`
- Exit-criteria block ends with `**Met** — Tier 11 16/16, Tier 7/8/9/10 retained at 14/25/20/22.`
- New `**Status:** ✅ Complete — see .planning/phases/05-portfolio-autonomy/` line appended
- Phase 6 / 7 / 8 sections untouched

### Task 4 — STRUCTURE.md: AOS Portfolio Autonomy Contract

Appended `## AOS Portfolio Autonomy Contract (Phase 5)` after the Phase 4 contract, covering:
- Entry point (`ark deliver` no-args from outside any project) + dispatcher route
- Components table (engine, deliver routing, audit class, env config)
- Priority formula (verbatim: `stuckness*3 + falling_health*2 + (monthly_headroom>20?1:0) + ceo_priority*5`)
- Signal sources (stuckness, falling_health, monthly_headroom, ceo_priority) with concrete signal definitions
- Tie-break rule (highest STATE.md mtime wins)
- 4 decision classes: SELECTED, DEFERRED_BUDGET, DEFERRED_HEALTHY, NO_CANDIDATE_AVAILABLE — each with audit context
- 24h cool-down rule (sqlite SELECT against class:portfolio history)
- CEO directive observed contract: +5 score boost, NOT a budget override (per Tier 11 run2 evidence)
- Backward compat: `--phase N` and in-project invocations bypass; static-grep guarantee `PROJECT_DIR` line < `portfolio_decide` line
- Production-safety guarantees (ARK_CREATE_GITHUB unset; no `gh repo create` in path; real DB md5 invariant)
- Tier 11 verify shape (16 checks enumerated)
- Cross-references to functions, plan history, related contracts

Note: `/Users/jongoldberg/vaults/automation-brain/STRUCTURE.md` and `/Users/jongoldberg/vaults/ark/STRUCTURE.md` are the same inode (44762697) — one edit covers both paths.

### Task 5 — SKILL.md: Phase 5 posture

Located at `~/.claude/skills/ark/SKILL.md` (not at vault root or `~/vaults/ark/`). Inserted a new `## AOS Posture (since Phase 5 — Portfolio Autonomy)` block after the Phase 4 posture, before `## When to use`. Documents portfolio_decide routing, priority formula, budget enforcement, CEO score-boost semantics, 4 decision classes, 24h cool-down, single-writer audit, and backward-compat invariants. Best-effort per plan instructions; not committed to git (path is outside any git repo).

## Verification — all green

```
$ bash scripts/ark-verify.sh --tier 11
  16 passed  0 warnings  0 failed  ⏭  96 skipped

$ bash scripts/ark-verify.sh --tier 7   →  14 passed  0 warnings  0 failed
$ bash scripts/ark-verify.sh --tier 8   →  25 passed  0 warnings  0 failed
$ bash scripts/ark-verify.sh --tier 9   →  20 passed  0 warnings  0 failed
$ bash scripts/ark-verify.sh --tier 10  →  22 passed  0 warnings  0 failed
```

Tier 7-11 totals: **97 passed, 0 failed.** Matches 05-06-SUMMARY.md baseline exactly.

## Acceptance criteria — all met

- [x] 8 REQ-AOS-23..30 rows present in REQUIREMENTS.md
- [x] STATE.md frontmatter `completed_phases: 5`, `total_plans: 41`, `completed_plans: 41`, status complete
- [x] STATE.md body has `Phase 5 — AOS: Portfolio Autonomy (complete)` section with 7-row plan table
- [x] STATE.md tail points to Phase 6 (Cross-Customer Learning Autonomy + Tier 12)
- [x] ROADMAP.md Phase 5 fully ticked + ✅ Complete status line
- [x] ROADMAP.md Phase 6/7/8 untouched
- [x] STRUCTURE.md has `AOS Portfolio Autonomy Contract (Phase 5)` section
- [x] All 4 decision-class names appear; priority formula present verbatim
- [x] SKILL.md (best-effort) updated with Phase 5 capabilities

## Deviations from Plan

### Auto-fixed Issues

None. All five tasks ran exactly as specified.

### Adaptations (non-deviations)

**1. SKILL.md path resolved at `~/.claude/skills/ark/SKILL.md`.**
- Plan said best-effort if absent at repo-root or `~/vaults/ark/`. SKILL.md does not exist at either; it lives in the global Claude skills directory. Updated in place. Path is outside any git repo, so no commit required for that file (still recorded in this SUMMARY).

**2. STRUCTURE.md is a single hardlinked file across two vault paths.**
- Both `/Users/jongoldberg/vaults/automation-brain/STRUCTURE.md` and `/Users/jongoldberg/vaults/ark/STRUCTURE.md` resolve to inode 44762697. Single edit on either path covers both; verified post-edit. Plan's `grep -q ... 2>/dev/null || grep -q ~/vaults/ark/...` fallback unnecessary in this environment.

**3. STATE.md `progress.percent` set to 71 (rather than 5/7 ≈ 71%).**
- Plan instruction matched: `(5/7 ≈ 71%)`. Recorded literal value 71.

## Self-Check: PASSED

**Files modified:**
- `/Users/jongoldberg/vaults/automation-brain/.planning/REQUIREMENTS.md` — REQ-AOS-23..30 appended (✓)
- `/Users/jongoldberg/vaults/automation-brain/.planning/STATE.md` — Phase 5 close (✓)
- `/Users/jongoldberg/vaults/automation-brain/.planning/ROADMAP.md` — Phase 5 ticked (✓)
- `/Users/jongoldberg/vaults/automation-brain/STRUCTURE.md` — Portfolio Autonomy Contract appended (✓)
- `/Users/jongoldberg/.claude/skills/ark/SKILL.md` — Phase 5 posture appended (✓)

**Files created:**
- `/Users/jongoldberg/vaults/automation-brain/.planning/phases/05-portfolio-autonomy/05-07-SUMMARY.md` — this file (✓)

**Commits:**
- `c771588` — Phase 5 Plan 05-07: STRUCTURE.md AOS Portfolio Autonomy Contract (✓)
- `648b2e2` — Phase 5 Plan 05-07: REQ-AOS-23..30 + STATE.md Phase 5 close + ROADMAP.md ticks (✓)
- (third commit at end of plan: this SUMMARY.md)

**Tier pass counts (post-doc-update; no code touched):**
- Tier 7:  14/14
- Tier 8:  25/25
- Tier 9:  20/20
- Tier 10: 22/22
- Tier 11: 16/16

**Phase 5 closed.** Next: Phase 6 — AOS: Cross-Customer Learning Autonomy.
