---
phase: 05-portfolio-autonomy
plan: 04
subsystem: portfolio-priority-engine
tags: [aos, phase-5, wave-2, audit, cooldown, bash-3, sqlite]
requirements:
  - REQ-AOS-25
dependency_graph:
  requires:
    - scripts/ark-portfolio-decide.sh::portfolio_scan_candidates (Plan 05-01)
    - scripts/ark-portfolio-decide.sh::portfolio_score_project (Plan 05-01)
    - scripts/ark-portfolio-decide.sh::_portfolio_budget_headroom (Plan 05-02)
    - scripts/ark-portfolio-decide.sh::_portfolio_ceo_priority (Plan 05-03)
    - scripts/ark-policy.sh::_policy_log (single audit writer)
    - scripts/lib/policy-db.sh::decisions table schema
  provides:
    - scripts/ark-portfolio-decide.sh::_portfolio_recently_deferred
    - scripts/ark-portfolio-decide.sh::_portfolio_row_to_json
    - "Production portfolio_decide emitting all 4 decision classes (overrides 05-01 stub)"
    - "Production portfolio_pick_winner with 24h cool-down filter (overrides 05-01)"
  affects:
    - "scripts/ark-deliver.sh (Plan 05-05 will source this lib for no-args branch)"
tech-stack:
  added: []
  patterns:
    - "function redefinition override (last-defined-wins) — preserves disjoint-section discipline"
    - "single-writer audit rule (_policy_log only writes; cool-down only reads policy.db)"
    - "graceful-degradation cool-down (missing sqlite3 / missing DB → not cooled, never crash)"
    - "BSD/GNU date dual fallback (-v vs -d) for ISO 8601 cutoff arithmetic"
key-files:
  created:
    - .planning/phases/05-portfolio-autonomy/05-04-SUMMARY.md
  modified:
    - scripts/ark-portfolio-decide.sh
decisions:
  - "Cool-down match key: project_path embedded in context JSON (substring LIKE) — avoids context schema migration"
  - "Reason class collapse: DEFERRED_BUDGET / DEFERRED_HEALTHY treated as separate cool-down namespaces (per CONTEXT.md Risks #1)"
  - "DEFERRED_BUDGET emitted PER over-cap candidate (one audit row per skipped project) for full traceability"
  - "DEFERRED_HEALTHY emitted ONLY for top-scoring healthy row when no winner — prevents log spam across all healthy candidates"
  - "Sentinel discipline: 05-04 changes confined to SECTION:audit-and-cooldown; production overrides via function redefinition (no edits to 05-01/02/03 regions)"
  - "Real ~/vaults/ark/observability/policy.db md5 verified unchanged across self-test (Tier 1 isolation)"
metrics:
  duration: "~12 minutes"
  completed: 2026-04-26
  lines_added: 333
  lines_removed: 0
  test_count_before: 30
  test_count_after: 40
  test_count_added: 10
---

# Phase 5 Plan 05-04: Audit-and-Cooldown Summary

Full `portfolio_decide` emitting all 4 decision classes (`SELECTED`, `DEFERRED_BUDGET`, `DEFERRED_HEALTHY`, `NO_CANDIDATE_AVAILABLE`) with serialized priority breakdown context, plus 24h cool-down filter against `class=portfolio decision=DEFERRED_*` audit history queried from `~/vaults/ark/observability/policy.db`.

## What landed

Three new functions inside `# === SECTION: audit-and-cooldown ===`:

1. `_portfolio_row_to_json <tsv_row>` — serializes the 8-field TSV scoring row to a JSON context object with all priority signals (`path`, `customer`, `phase`, `stuckness`, `falling_health`, `budget_headroom`, `ceo_priority`, `total`). String fields backslash-and-quote escaped; numeric fields emitted as bare integers.
2. `_portfolio_recently_deferred <project_path> <reason_class>` — returns 0 (cooled) iff a `class=portfolio decision=DEFERRED_${reason_class}` row exists for `project_path` within the last 24h. Reads `$ARK_POLICY_DB` (test override) or `$ARK_HOME/observability/policy.db`. SQL injection–safe (single quotes doubled). Graceful degradation: missing `sqlite3` or missing DB → returns 1 (not cooled).
3. `portfolio_pick_winner [root]` (override) — same contract as 05-01 stub, but additionally skips: (a) projects with `budget_headroom == 0` (Plan 05-02 budget filter); (b) projects recently DEFERRED_BUDGET when over budget; (c) projects recently DEFERRED_HEALTHY when stuckness=0 + falling_health=0 + ceo_priority=0.
4. `portfolio_decide [root]` (override) — replaces 05-01 stub. Algorithm:
    - Empty portfolio → emit `NO_CANDIDATE_AVAILABLE` with `{root}` context.
    - Walk every scored row: emit `DEFERRED_BUDGET` per over-cap (headroom=0) row (skipping cooled-down ones).
    - Pick winner via overridden `portfolio_pick_winner` (applies budget + cool-down filters).
    - If no winner: emit `DEFERRED_HEALTHY` for top-scoring healthy-but-skipped row, OR `NO_CANDIDATE_AVAILABLE` if all candidates were budget-deferred.
    - Otherwise emit `SELECTED` with full priority-breakdown JSON; echo winner path to stdout.

## Self-test results

- Baseline (Plans 05-01/02/03): 30/30
- After 05-04: **40/40** (+10 new assertions)

New assertions:

1. Over-budget customer (acme) emits DEFERRED_BUDGET
2. Healthy candidate emits SELECTED
3. Context JSON contains `total` field (full breakdown)
4. Empty portfolio emits NO_CANDIDATE_AVAILABLE
5. Cool-down detects DEFERRED_BUDGET within 24h
6. Cool-down correctly ignores >24h-old row
7. Recently DEFERRED_HEALTHY project skipped from pool by `portfolio_pick_winner`
8. All 4 decision classes present as string literals in the file
9. `_portfolio_row_to_json` produces valid JSON (validated via `python3 -c json.loads`)
10. No `INSERT INTO decisions` in production code section (single-writer rule)

All four decision classes exercised in tests: SELECTED, DEFERRED_BUDGET, DEFERRED_HEALTHY, NO_CANDIDATE_AVAILABLE.

## Verification claims

- `bash scripts/ark-portfolio-decide.sh test` → **40/40 PASSED**
- `grep -c "portfolio_decide" scripts/ark-portfolio-decide.sh` → 14 (≥2)
- `grep -c '_policy_log "portfolio"' scripts/ark-portfolio-decide.sh` → 8 (≥4: one per decision class)
- `bash -c 'source scripts/ark-portfolio-decide.sh; type -t _portfolio_recently_deferred'` → `function`
- SECTION:budget-reader md5 unchanged: `a54a3e71c6a253443762371c908bb75f` (byte-identical to pre-05-04)
- SECTION:ceo-directive md5 unchanged: `dc504ee92b0304ad6981a372efaa3beb` (byte-identical to pre-05-04)
- Real `~/vaults/ark/observability/policy.db` md5 unchanged across self-test (Tier 1 isolation invariant verified inside test)

## Sentinel discipline

All production code added strictly between `# === SECTION: audit-and-cooldown (Plan 05-04) ===` and `# === END SECTION: audit-and-cooldown ===`. The 05-01-owned `portfolio_decide` and `portfolio_pick_winner` (lines 274-306, 240-272 respectively) were **not** modified — instead, new definitions inside the SECTION redefine those functions (bash last-definition-wins). Self-test assertions appended before the existing pass/fail summary block.

## Single-writer rule

`_policy_log` remains the sole writer to the `decisions` table. The new `_portfolio_recently_deferred` only `SELECT`s; the self-test fixture's mock-DB `INSERT`s are gated behind the `BASH_SOURCE[0] == $0 && $1 == test` self-test guard and write to an isolated `$TMP_VAULT/observability/policy.db` via `$ARK_POLICY_DB` override. Verified by assertion #10: `awk` confirms zero `INSERT INTO decisions` lines exist before the self-test guard line.

## Self-Check: PASSED

- File `scripts/ark-portfolio-decide.sh`: FOUND (modified, +333 lines, 0 removed)
- File `.planning/phases/05-portfolio-autonomy/05-04-SUMMARY.md`: FOUND (this file)
- Self-test: 40/40 passing
- Sentinel md5 invariants: all 2 disjoint sections (budget-reader, ceo-directive) byte-identical
