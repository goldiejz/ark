---
phase: 05-portfolio-autonomy
plan: 06
subsystem: portfolio-priority-engine
tags: [aos, phase-5, wave-4, exit-gate, verify, bash-3, isolation]
requirements:
  - REQ-AOS-29
  - REQ-AOS-30
dependency_graph:
  requires:
    - scripts/ark-portfolio-decide.sh::portfolio_decide (Plans 05-01..05-04)
    - scripts/ark-deliver.sh::portfolio routing (Plan 05-05)
    - scripts/lib/policy-db.sh::db_init
  provides:
    - "Tier 11 — Portfolio autonomy verify suite (16 checks)"
  affects:
    - "scripts/ark-verify.sh — adds tier_11 dispatch arm"
tech-stack:
  added: []
  patterns:
    - "NEW-W-1 isolation: mktemp -d for tmp vault + tmp portfolio root"
    - "ARK_POLICY_DB redirection to isolate audit-DB writes"
    - "real-vault policy.db md5 invariant (before/after capture)"
    - "static-grep gate verification (PROJECT_DIR before portfolio_decide)"
    - "synthetic 3-project / 2-customer fixture under mktemp"
key-files:
  created:
    - .planning/phases/05-portfolio-autonomy/05-06-SUMMARY.md
  modified:
    - scripts/ark-verify.sh
decisions:
  - "Integrated Tier 11 into existing run_check / run_existence_check framework rather than the inline assert_eq/RETURN-trap pattern in the plan skeleton — matches Tier 9 + Tier 10 idiom, reuses pass/fail counters, single REPORT path."
  - "CEO-directive override test (run2) verifies CURRENT contract: budget filter is hard — CEO +5 score boost cannot override DEFERRED_BUDGET. acme-stuck (CEO-favored, blocked, score=6+5=11) is excluded from winner pool by budget filter; foo-c (healthy, score=1, no CEO bonus) still wins. Plan brief flagged this ambiguity; observed behavior asserted as-is."
  - "Cool-down test (run3) uses DEFERRED_HEALTHY (not DEFERRED_BUDGET) to keep test isolated from the budget filter. Mirrors self-test idiom."
  - "Run4 (25h cool-down expiry): asserts a SELECTED row appears + non-empty winner output. Doesn't pin the winner identity because score arithmetic (acme-stuck blocked=2*3 + cap-headroom_bonus=1 = 7 vs foo-c stk=0 + headroom=1 = 1) makes acme-stuck the heuristic winner under loosened budget — but the test's purpose is cool-down expiry, not winner identity, so we just confirm the pipeline didn't filter everything."
  - "Backward-compat check is static-grep (PROJECT_DIR appears before portfolio_decide line in ark-deliver.sh) — proves the no-args branch is gated, without spinning a real ark-deliver.sh subprocess inside the test (which would risk side effects on a real project cwd)."
  - "ARK_CREATE_GITHUB stays UNSET throughout. No GitHub API calls in portfolio path — additionally enforced by static grep for 'gh repo create' over portfolio + deliver scripts."
  - "Did NOT modify tier_1..tier_10. Tier 11 inserted between Tier 10 cleanup and the Generate-report block; sign-off list extended with Tier 11."
metrics:
  duration: ~20min
  tasks_completed: 1
  completed_date: 2026-04-26
---

# Phase 5 Plan 05-06: Tier 11 verify suite — Phase 5 exit gate — Summary

**One-liner:** Added Tier 11 to `scripts/ark-verify.sh` — a 16-check suite that exercises portfolio_decide across a synthetic 3-project / 2-customer mktemp fixture, asserting all 4 decision classes fire (SELECTED, DEFERRED_BUDGET, DEFERRED_HEALTHY, NO_CANDIDATE_AVAILABLE), CEO override semantics, 24h cool-down (and expiry), backward-compat for project-cwd invocations, and the real-vault policy.db md5 invariant — Tier 7-10 regression-clean.

## What was built

### Task 1 — `scripts/ark-verify.sh`

Added `# ━━━ Tier 11: Portfolio autonomy under stress (AOS Phase 5) ━━━` block (~190 lines) between Tier 10 cleanup and the report-generation section. Integrates with the existing `run_check` / `run_existence_check` / `should_run_tier` framework. Updated the sign-off section listing to mention Tier 11.

### Tier 11 fixture

```
mktemp tmp vault:
  observability/policy.db      (isolated audit DB)
  scripts/ark-portfolio-decide.sh, ark-policy.sh
  scripts/lib/...              (policy-db.sh, policy-config.sh, gsd-shape.sh)
  customers/acme/policy.yml    (90% used / 100% cap → over-cap)
  customers/foo/policy.yml     (30% used / 100% cap → headroom)

mktemp tmp portfolio:
  acme-a/                      acme customer, healthy, in-progress
  acme-stuck/                  acme customer, blocked (stuckness=2)
  foo-c/                       foo customer, healthy, in-progress
```

## Tier 11 results — 16/16 PASS

```
━━━ Tier 11: Portfolio autonomy ━━━
  ✅ T11: ark-portfolio-decide.sh present
  ✅ T11: ark-portfolio-decide.sh syntax valid
  ✅ T11: ark-portfolio-decide.sh self-test passes (40/40)
  ✅ T11: ark-deliver.sh has portfolio_decide call
  ✅ T11: ark dispatcher documents ARK_PORTFOLIO_ROOT
  ✅ T11: run1: foo-c wins over over-budget acme projects
  ✅ T11: run1: audit has 1 SELECTED row
  ✅ T11: run1: audit has DEFERRED_BUDGET rows for over-cap acme projects (>=1)
  ✅ T11: run1: SELECTED context_json includes total + customer=foo
  ✅ T11: run2: CEO directive on over-budget project does NOT override budget filter; foo-c still wins
  ✅ T11: run3: 1h-old DEFERRED_HEALTHY keeps foo-c out of winner pool
  ✅ T11: run4: 25h-old cool-down expired — winner SELECTED
  ✅ T11: run5: empty portfolio emits NO_CANDIDATE_AVAILABLE
  ✅ T11: ark-deliver.sh portfolio_decide is gated behind project-detection (PROJECT_DIR appears before portfolio_decide call)
  ✅ T11: no 'gh repo create' in portfolio code path
  ✅ T11: isolation: real vault policy.db unchanged before/after Tier 11

  Verification: ✅ APPROVED
  16 passed  0 warnings  0 failed  ⏭  96 skipped
```

## Tier 7-10 regression — all green

```
=== Tier 7 ===   14 passed  0 warnings  0 failed  ⏭  87 skipped
=== Tier 8 ===   25 passed  0 warnings  0 failed  ⏭  76 skipped
=== Tier 9 ===   20 passed  0 warnings  0 failed  ⏭  92 skipped
=== Tier 10 ===  22 passed  0 warnings  0 failed  ⏭  89 skipped
```

Baselines from Plan 05-05 SUMMARY: 14/14, 25/25, 20/20, 22/22. **Match.**

## CEO-override observed contract

For Phase 5 Wave 4 record: with `programme.md::## Next Priority` pointing to `acme-stuck` (blocked, stuckness=2) while `acme` is over its 80% monthly cap:

- `_portfolio_ceo_priority(acme-stuck)` → 1 → score boost +5
- raw heuristic total for acme-stuck: stuckness * 3 + 0 + 0 + 1 * 5 = **11**
- `_portfolio_budget_headroom(acme)` → 0 (over-cap)
- `portfolio_pick_winner` filters rows where `headroom <= 0` → acme-stuck excluded from winner pool
- foo-c (healthy, no CEO bonus, total=1) wins by default

**Conclusion:** the budget filter is hard. CEO directive is a *score* boost, not an *override*. If a future requirement wants CEO to override a budget DEFERRED, that's a contract change for a later plan — Tier 11 documents the current behavior.

## Isolation guarantees

| Invariant | Mechanism | Result |
|-----------|-----------|--------|
| Real `~/vaults/ark/observability/policy.db` md5 unchanged | `md5 -q` capture before/after `tier_11`; assertion in last check | ✅ |
| No real GitHub API calls | `ARK_CREATE_GITHUB` left UNSET; static `grep -l 'gh repo create'` over portfolio scripts returns empty | ✅ |
| All test files under mktemp `-d` | `T11_VAULT`, `T11_PORT`, `T11_EMPTY` all created via `mktemp -d -t ...`; cleanup via `rm -rf` | ✅ |
| No real-`~/code` writes | Test fixture uses `T11_PORT` (mktemp), not `$HOME/code` | ✅ |

## Acceptance criteria — all met

- [x] `bash scripts/ark-verify.sh --tier 11` → 16 pass, 0 fail
- [x] `tier_11` block defined; `should_run_tier 11` arm reachable
- [x] `bash scripts/ark-verify.sh --tier 7`  still 14/14 (REQ-AOS-30)
- [x] `bash scripts/ark-verify.sh --tier 8`  still 25/25
- [x] `bash scripts/ark-verify.sh --tier 9`  still 20/20
- [x] `bash scripts/ark-verify.sh --tier 10` still 22/22
- [x] Real `~/vaults/ark/observability/policy.db` md5 unchanged after Tier 11 run
- [x] No new files created under real `~/code/`

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 — Bug] First implementation of "ark-deliver.sh portfolio_decide is in no-args branch (gated)" used a fragile awk+xargs+sh -c pipeline with nested quoting that resolved to a no-output condition.**

- **Found during:** initial Tier 11 dry-run (15/16, 1 fail)
- **Issue:** the awk pipeline `awk '/portfolio_decide/{print NR}' | head -1 | xargs -I{} sh -c 'awk "NR<{}..."` produced no `OK` output due to backslash-escaping inside double-quoted `run_check` argument
- **Fix:** simplified to `grep -n` line-number comparison: `pdr=$(grep -n PROJECT_DIR ... | head -1 | cut -d: -f1)` and `pdc=$(grep -n portfolio_decide ...)` — assert `pdr < pdc`. Same semantic intent (project-detection appears before portfolio_decide in source order), no nested quoting.
- **Files modified:** `scripts/ark-verify.sh` (one check rewritten)
- **Verified:** Tier 11 16/16 after fix

### Plan-skeleton deviations (intentional)

**2. [Pattern adaptation] Did NOT use the inline `assert_eq` + RETURN-trap pattern from the plan skeleton.**

- **Reason:** Tier 9 and Tier 10 use the existing `run_check` / `run_existence_check` framework with global PASS/WARN/FAIL/RESULTS counters. Inserting an inline `tier_11()` function with its own counters would have:
  - duplicated reporting logic
  - bypassed the per-tier RESULTS array used by the report-generation block
  - required a separate `case --tier` arm dispatcher (the existing dispatch is `should_run_tier "$tier"` flag inside `run_check`)
- **Decision:** match Tier 10 idiom precisely — `if should_run_tier 11; then` block + `run_check 11 ...` calls. Cleaner, consistent, no framework duplication.

**3. [Cool-down test] Used `DEFERRED_HEALTHY` (not `DEFERRED_BUDGET`) for the cool-down assertion.**

- **Reason:** the brief said insert a `class:portfolio decision:DEFERRED_HEALTHY` row 1h ago and assert filtering. With acme over-budget, acme-* projects are already filtered by the budget rule — testing cool-down via DEFERRED_HEALTHY on foo-c isolates the cool-down filter from the budget filter. Mirrors the production self-test (Plan 05-04) idiom.

## Self-Check: PASSED

**Files exist:**
- `/Users/jongoldberg/vaults/automation-brain/scripts/ark-verify.sh` — modified (✓)
- `/Users/jongoldberg/vaults/automation-brain/.planning/phases/05-portfolio-autonomy/05-06-SUMMARY.md` — created (✓)

**Commit exists:**
- `d1e2c31` — Phase 5 Plan 05-06: Tier 11 verify suite — Phase 5 exit gate (✓)

**Tier 11 pass count:** 16/16
**Tier 7-10 pass counts:** 14/14, 25/25, 20/20, 22/22 — unchanged from baseline
**Real-DB md5 invariant:** held (asserted by Tier 11 internally)
