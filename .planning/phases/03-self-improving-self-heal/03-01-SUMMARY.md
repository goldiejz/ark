---
phase: 03-self-improving-self-heal
plan: 01
subsystem: aos-learner-foundation
status: complete
tags: [aos, phase-3, learner, outcome-tagger, sqlite]
requires:
  - scripts/lib/policy-db.sh        # db_path(), schema
  - scripts/ark-policy.sh           # _policy_log writes the rows tagger updates
provides:
  - tagger_infer_outcome
  - tagger_patch_outcome
  - tagger_run_window
affects:
  - observability/policy.db (UPDATE on `outcome` column only)
tech-stack:
  added: [sqlite3 UPDATE flow, awk-bounded self-scan]
  patterns: [single-writer-rule, idempotent-update, bash-3-compat]
key-files:
  created:
    - scripts/lib/outcome-tagger.sh
  modified: []
decisions:
  - Adopted the tagger_* function names from SUPERSEDES.md/the user prompt rather than the older outcome_* names in 03-01-PLAN.md (SUPERSEDES wins).
  - Git-commit success heuristic restricted to dispatch-flavoured classes only (dispatch, dispatch_failure, self_heal, self_improve). Budget/zero_tasks decisions cannot be "succeeded" by a coincident commit — they don't produce code.
  - Conflict policy: tagger refuses to overwrite an existing differing outcome unless ARK_TAGGER_FORCE=true. Idempotent re-patch with same value is exit 0.
  - run_window deliberately tags ALL outcome-IS-NULL rows in the window, including chain follow-ups. Those are mostly classified ambiguous (no further chain), which is the right answer.
metrics:
  tests_passing: 18
  duration_seconds: ~10 (self-test wall time)
  completed: 2026-04-26
---

# Phase 3 Plan 03-01: outcome-tagger.sh Summary

Built the foundational outcome-tagging library every other Phase 3 component depends on. Single SQLite-backed writer for the `outcome` column of the policy decisions log; mirror of Phase 2's `_policy_log` single-INSERT writer rule. SUPERSEDES.md governed: SQL UPDATE replaces the originally-planned jq rewrite.

## Public API

`scripts/lib/outcome-tagger.sh` (sourceable, executable, Bash-3 compatible):

| Function | Signature | Returns |
|---|---|---|
| `tagger_infer_outcome` | `<decision_id> [project_dir] [window_minutes]` | echoes `success` \| `failure` \| `ambiguous` |
| `tagger_patch_outcome` | `<decision_id> <outcome>` | `0` patched or no-op, `2` conflict (refuses overwrite unless `ARK_TAGGER_FORCE=true`) |
| `tagger_run_window` | `<since_iso8601> [until_iso8601]` | echoes `tagged: N (success: a, failure: b, ambiguous: c)` |

Configuration:
- `ARK_POLICY_DB` — overrides DB path (test isolation)
- `ARK_TAGGER_WINDOW_MIN` — minutes, default `10` (or `policy_config_get phase3.outcome_window_minutes`)
- `ARK_TAGGER_PROJECT_DIR` — project root for delivery-log + git scan, default `$PWD`
- `ARK_TAGGER_FORCE=true` — allow overwriting an existing differing outcome

## Inference rules (heuristic order)

1. **Failure** — there exists a later row with `class='escalation' AND correlation_id=<decision_id>` within the window, OR a `class='self_heal' AND decision='REJECTED'` row in the same chain.
2. **Success** — any of:
   - A delivery-log file under `<project_dir>/.planning/delivery-logs/` mentions the decision_id and a success/complete/PROMOTED marker.
   - The decision's class is dispatch-flavoured (`dispatch`, `dispatch_failure`, `self_heal`, `self_improve`) AND a git commit landed in `<project_dir>` between the decision's `ts` and `ts + window`.
   - A subsequent decision in the same correlation chain has `decision NOT LIKE 'ESCALATE_%'` (the system kept going without escalating).
3. **Ambiguous** — no signal in the window.

## Idempotency guarantee

- `tagger_patch_outcome <id> <v>` — if existing outcome already equals `<v>`, exit 0 with no SQL write. If it differs, exit 2 and refuse to clobber (unless `ARK_TAGGER_FORCE=true`). Never widens privilege beyond the `outcome` column.
- `tagger_run_window` — only selects rows with `outcome IS NULL`. Re-running over the same window after a successful pass yields `tagged: 0 (success: 0, failure: 0, ambiguous: 0)` (verified in self-test step 4).
- Schema is never mutated. `schema_version=1` invariant asserted post-patch (self-test step 5).

## Single-writer rule (mirrors Phase 2 NEW-B-2)

| Field | Sole writer |
|---|---|
| New row INSERT (all columns except outcome) | `_policy_log` (in `scripts/ark-policy.sh`, via `db_insert_decision`) |
| `outcome` UPDATE | `tagger_patch_outcome` (in `scripts/lib/outcome-tagger.sh`) |

No other module writes the `outcome` column. Downstream Phase 3 modules (03-02 learner, 03-04 digest, 03-05 ark-deliver hook) consume tagger outputs but never UPDATE the column directly.

## Self-test (`bash scripts/lib/outcome-tagger.sh test`)

18 assertions covering:
- 5 synthetic inference cases (chain success, delivery-log success, git-commit success, escalation failure, ambiguous-no-signal)
- patch persistence + idempotent re-patch + conflict refusal + FORCE override
- run_window tagging of all 5 primary decisions correctly
- idempotency: re-run NULL-count unchanged
- schema_version=1 invariant after patches
- Bash-3 compat scan of pre-test code region (no `declare -A`, no `mapfile`)

Result: `✅ ALL OUTCOME-TAGGER TESTS PASSED (18/18)`.

## Deviations from Plan

1. **API names follow SUPERSEDES.md / user prompt, not 03-01-PLAN.md.** Plan specified `outcome_classify`/`outcome_tag_decision`/`outcome_tag_window`; SUPERSEDES.md and the executor prompt specified `tagger_infer_outcome`/`tagger_patch_outcome`/`tagger_run_window`. SUPERSEDES is the authoritative override per its own header. Downstream consumers (03-02, 03-04, 03-05) must use the tagger_* names.
2. **Patcher uses `sqlite3 UPDATE`, not `jq`.** Per SUPERSEDES (substrate change to SQLite from Phase 2.5). Plan's jq-rewrite mechanism is no longer applicable.
3. **Conflict-policy stricter than original plan.** Plan said "if non-null AND classification differs, leave existing value... return 0". I return 2 instead (with a stderr note) because silently swallowing a conflict makes upstream bugs invisible. `ARK_TAGGER_FORCE=true` provides the explicit override path. Rule 2 (auto-add safety/correctness functionality).
4. **Git-commit signal scoped to dispatch-class decisions only** (Rule 1 — bug fix during self-test). Without this restriction, every decision (including budget/zero_tasks) was tagged success because any commit in the project was treated as evidence. Restricted to `dispatch|dispatch_failure|self_heal|self_improve` classes which are the only classes whose decisions actually produce code.

## Verification

- `bash scripts/lib/outcome-tagger.sh test` → exit 0, 18/18 pass
- `bash scripts/lib/policy-db.sh test` → still passes (no regression)
- `bash scripts/ark-policy.sh test` → still passes 15/15 (no regression)
- `bash -c 'source scripts/lib/outcome-tagger.sh && type tagger_infer_outcome tagger_patch_outcome tagger_run_window'` → exits 0
- `test -x scripts/lib/outcome-tagger.sh` → true

## Self-Check: PASSED

- Created file exists: scripts/lib/outcome-tagger.sh ✅
- File is executable: ✅
- Self-test passes 18/18: ✅
- No regressions in dependency lib tests: ✅
