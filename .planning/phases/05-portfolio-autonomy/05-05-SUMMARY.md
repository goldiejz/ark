---
phase: 05-portfolio-autonomy
plan: 05
subsystem: portfolio-priority-engine
tags: [aos, phase-5, wave-3, deliver, dispatcher, bash-3, backward-compat]
requirements:
  - REQ-AOS-24
  - REQ-AOS-28
dependency_graph:
  requires:
    - scripts/ark-portfolio-decide.sh::portfolio_decide (Plans 05-01..05-04)
    - scripts/ark-policy.sh::_policy_log (single audit writer)
    - scripts/lib/policy-db.sh (sqlite audit DB init)
  provides:
    - "ark-deliver.sh no-args portfolio routing branch (REQ-AOS-24)"
    - "ark dispatcher help text + ARK_PORTFOLIO_ROOT env doc"
  affects:
    - "ark deliver entry point — no-args from non-project cwd now routes through portfolio_decide"
tech-stack:
  added: []
  patterns:
    - "set +u/set -u bracket around sourced library that uses Bash-3 array idioms"
    - "early-branch in main() (not at parse-time) — log() and color vars must be defined first"
    - "broad project detection: STATE.md OR policy.yml OR PROJECT.md OR ROADMAP.md (per executor brief)"
    - "byte-identical fall-through: WINNER becomes new PROJECT_DIR; preflight + run_phase loops untouched"
key-files:
  created:
    - .planning/phases/05-portfolio-autonomy/05-05-SUMMARY.md
  modified:
    - scripts/ark-deliver.sh
    - scripts/ark
decisions:
  - "Insert portfolio block inside main() (line 578) rather than at top-level before preflight() definition (line 92): log() and color vars are defined later in the file, so top-level placement would run before they exist. Functional acceptance — block runs before preflight() is CALLED — is preserved."
  - "Use set +u around source ark-portfolio-decide.sh + portfolio_decide call: the library uses ${_PORTFOLIO_SAVED_ARGS[@]} which trips set -u under bash 3 when array is empty. Restore set -u immediately after. Localized fix avoids cross-cutting library refactor."
  - "Project detection broadened from plan-spec (only ROADMAP.md) to executor-brief (STATE.md OR policy.yml OR PROJECT.md OR ROADMAP.md). Either makes 'cwd is a project' true → portfolio engine skipped. Broader detection is strictly safer (more false-negatives → fewer accidental portfolio routes)."
  - "On empty winner (no candidate selected) — exit 1 with friendly WARN log pointing to ESCALATIONS.md. Audit log already records NO_CANDIDATE_AVAILABLE / DEFERRED_* via portfolio_decide; no double-logging."
metrics:
  duration: ~25min
  tasks_completed: 2
  completed_date: 2026-04-26
---

# Phase 5 Plan 05-05: ark-deliver no-args portfolio routing + dispatcher refresh — Summary

**One-liner:** `ark deliver` from a non-project directory now sources `ark-portfolio-decide.sh::portfolio_decide`, audit-logs the SELECTED winner, `cd`s into it, and runs the existing full-delivery flow byte-identically — backward-compat preserved for all flagged invocations.

## What was built

### Task 1 — `scripts/ark-deliver.sh`

1. Header usage block updated to document the two no-args modes (in-project full delivery vs portfolio routing) and the `ARK_PORTFOLIO_ROOT` env var.
2. Inside `main()`, immediately before `preflight`, a new branch:
   - Triggers when `MODE=full`, no `--from-spec / --phase / --resume`, AND none of `.planning/STATE.md / policy.yml / PROJECT.md / ROADMAP.md` exist in cwd.
   - Logs `[INFO] No project in cwd — routing via portfolio priority engine...`.
   - Sources `$VAULT_PATH/scripts/ark-portfolio-decide.sh` under `set +u` (the lib uses bash-3 array idioms incompatible with strict-mode); calls `portfolio_decide "${ARK_PORTFOLIO_ROOT:-$HOME/code}"`; restores `set -u`.
   - On empty winner → friendly WARN + `exit 1` (audit log already populated by `portfolio_decide`).
   - On valid winner path → `cd "$WINNER"`, reassigns `PROJECT_DIR`, falls through to existing `preflight` + `run_phase` loops untouched.
3. Inline `--help` block updated to document portfolio mode + `ARK_PORTFOLIO_ROOT`.

### Task 2 — `scripts/ark` (dispatcher)

1. `cmd_help` deliver line refreshed: `Run autonomous delivery. With no args from outside a project, picks portfolio winner.`
2. New env-var documentation: `ARK_PORTFOLIO_ROOT  Root for 'ark deliver' no-args portfolio scan (default: ~/code)`.
3. `deliver)` dispatch line **unchanged** — already a clean `shift; bash "$VAULT_PATH/scripts/ark-deliver.sh" "$@"` pass-through.

## Verification

`bash -n` clean on both scripts. Acceptance grep counts:
- `portfolio_decide` references in deliver: 2 (call + comment) — required ≥1 ✅
- `REQ-AOS-24` references: 2 (header + branch comment) ✅
- `ARK_PORTFOLIO_ROOT` references in deliver: 3 ✅
- `ark-portfolio-decide.sh` source references: 3 ✅
- `portfolio winner` mention in `ark` help: 1 ✅
- Dispatch passthrough match: exactly 1 (line 264, unchanged) ✅
- Bare `read -p` lines (excluding `# AOS: intentional gate`): 0 ✅
- Branch insertion (line 578) before `preflight` call (line 628): ✅

### Smoke tests (`mktemp -d` isolation, fresh vault, `ARK_CREATE_GITHUB` unset)

**Test 1 — no-args, non-project cwd, 2-project portfolio (proj-x active, proj-y blocked):**
- `[INFO] No project in cwd — routing via portfolio priority engine...` ✅
- `[OK] Portfolio winner: $TMPPORT/proj-y` (blocked → stuckness=2 → 2*3 + headroom_bonus = 7 — highest score) ✅
- After cd, normal flow proceeds: `[INFO] Running pre-flight checks...` then `[ERROR] No .parent-automation/` (expected: tmp project has no automation snapshot — proves cd happened and existing flow ran) ✅
- Audit DB row: `portfolio | SELECTED | highest_priority_total=7` (count=1) ✅

**Test 2 — backward compat, `--phase 1` from inside a project:**
- No `routing via portfolio priority engine` log → portfolio NOT engaged ✅
- `Mode: single-phase` → existing flow ✅ (REQ-AOS-28)

**Test 3 — backward compat, no-args from inside a project:**
- No portfolio routing log ✅ (cwd has `.planning/ROADMAP.md` → branch skipped)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — Blocking] `set -u` incompatibility with sourced portfolio lib**
- **Found during:** Smoke Test 1 (first run).
- **Issue:** `ark-deliver.sh` runs under `set -uo pipefail`. Sourcing `ark-portfolio-decide.sh` immediately tripped: `_PORTFOLIO_SAVED_ARGS[@]: unbound variable` — the lib references `${_PORTFOLIO_SAVED_ARGS[@]}` (bash-3 array trick) which `set -u` rejects when the array is empty.
- **Fix:** Wrapped the `source` + `portfolio_decide` call in `set +u` … `set -u`. Localized; doesn't touch the sourced lib (which is owned by Plans 05-01..05-04). Re-running smoke test after fix → all assertions green.
- **Files modified:** `scripts/ark-deliver.sh` (2 lines: `set +u` before source, `set -u` after `WINNER=` assignment).

### Plan-spec deviations (intentional adjustments documented up-front)

**2. [Rule 3 — Adjusted] Branch placement: inside `main()`, not top-level**
- **Plan said:** "Insert AFTER arg-parsing (around line 51) and BEFORE preflight()."
- **Why adjusted:** `log()` (line 72) and the color vars (lines 55-59) are defined AFTER line 51. Top-level placement would call `log INFO ...` before `log` exists. The functionally-equivalent location is inside `main()` immediately before `preflight` is invoked — preserves "branch runs before preflight" while keeping all dependencies in scope.
- **Net result:** branch inserted at line 578 in `main()`; preflight CALL is at line 628; verified `BRANCH_LINE < PREFLIGHT_CALL`. Acceptance criterion ("branch is BEFORE preflight() at runtime") satisfied.

**3. [Rule 3 — Broadened] Project-detection criteria**
- **Plan said:** detect "cwd is a project" via `.planning/ROADMAP.md`.
- **Executor brief said:** detect via `.planning/STATE.md` OR `policy.yml` OR `PROJECT.md`.
- **Adopted:** OR'd union of all four (STATE.md, policy.yml, PROJECT.md, ROADMAP.md). Strictly safer — more files match → "is a project" true → portfolio routing skipped → backward compat preserved on more cases. No false positives possible.

## Authentication Gates

None — pure shell-script integration.

## Self-Check: PASSED

- [x] `scripts/ark-deliver.sh` exists and contains `portfolio_decide` (2x), `REQ-AOS-24` (2x), `ARK_PORTFOLIO_ROOT` (3x), `ark-portfolio-decide.sh` source ref.
- [x] `scripts/ark` exists and contains `portfolio winner` in help; dispatch passthrough at line 264 unchanged.
- [x] `bash -n` clean on both files.
- [x] Smoke test 1 (no-args portfolio routing): 4/4 assertions pass.
- [x] Smoke test 2 (backward compat `--phase 1`): pass.
- [x] Smoke test 3 (backward compat no-args in-project): pass.
- [x] Audit DB shows `class=portfolio decision=SELECTED` row after no-args invocation.
