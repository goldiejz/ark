---
phase: 03-self-improving-self-heal
plan: 07
subsystem: ark-verify (Tier 9)
tags: [aos, phase-3, verify, regression-contract, isolation, sqlite]
requirements: [REQ-AOS-14]
dependency_graph:
  requires:
    - 03-01-SUMMARY.md  # outcome-tagger.sh
    - 03-02-SUMMARY.md  # policy-learner.sh + scoring/classify
    - 03-03-SUMMARY.md  # learner_apply_pending (auto-patch policy.yml)
    - 03-04-SUMMARY.md  # policy-digest.sh (learner_write_digest)
    - 03-05-SUMMARY.md  # ark-deliver post-phase trigger
    - 03-06-SUMMARY.md  # ark learn subcommand
  provides:
    - "Tier 9 regression contract for AOS Phase 3"
    - "Synthetic-fixture pipeline gate against learner/tagger/patcher drift"
  affects:
    - scripts/ark-verify.sh (added 185 lines, Tier 9 block)
tech-stack:
  added: []  # No new deps; Tier 9 reuses python3 + sqlite3 already required by Phase 2.5
  patterns:
    - "Tier 9 isolation mirrors Phase 2 NEW-W-1 (tmp ARK_HOME + ARK_POLICY_DB; md5 before/after)"
    - "Synthetic data via INSERT INTO decisions (Phase 2.5 SQLite substrate, not JSONL jq)"
    - "Idempotency assertion: re-run produces no new self_improve audit entries"
key-files:
  created: []
  modified:
    - scripts/ark-verify.sh
decisions:
  - "Synthetic fixture composition: 5 patterns × 6 rows = 30 INSERTs covering PROMOTE / DEPRECATE / mediocre-middle / 2 true-blockers"
  - "Auto-apply triggered via LEARNER_AUTO_APPLY=1 so Tier 9 covers full pipeline (score → classify → sidecar → apply → audit → commit)"
  - "Isolation guarantee enforced via md5 of $VAULT_PATH/observability/policy.db before+after — tier 9 fails loudly if it ever poisons the real DB"
  - "Pre-existing Tier 7 (13/14) and Tier 8 (24/25) failures left untouched; out of scope for this plan (deviation Rule SCOPE BOUNDARY)"
metrics:
  duration_minutes: ~10
  completed_date: 2026-04-26
  checks_added: 20
  lines_added: 185
---

# Phase 03 Plan 07: Tier 9 Verify Suite Summary

Add a Tier 9 ("Self-improving self-heal") block to `scripts/ark-verify.sh` that locks the AOS Phase 3 regression contract: a synthetic SQLite audit log with 5 known patterns must produce exactly 1 promotion, 1 deprecation, zero entries for the mediocre-middle pattern, and zero entries for either true-blocker class — auto-patched into a tmp `policy.yml`, audit-trailed in a tmp `policy.db`, digest-written, git-committed, and idempotent on re-run, all inside an isolated tmp `ARK_HOME` that md5-verifies the real vault DB was never touched.

## What changed

**`scripts/ark-verify.sh`** — added 185 lines containing:

1. A new Tier 9 header block.
2. 9 wiring checks: `outcome-tagger.sh`, `policy-learner.sh`, `policy-digest.sh` exist + syntax-valid; `ark learn` subcommand registered; `ark-deliver.sh` has post-phase learner trigger; `policy-learner self-test` passes.
3. 11 synthetic-pipeline checks against an isolated tmp vault.
4. A sign-off-table addition that lists Tiers 7, 8, 9 alongside the original 1–6.

## Synthetic fixture composition

30 rows inserted directly into `$TIER9_TMP/observability/policy.db` via `python3 + sqlite3`:

| Pattern | (class, decision, dispatcher, complexity)               | n | success/failure | success_rate | Expected verdict |
| ------- | ------------------------------------------------------- | - | --------------- | ------------ | ---------------- |
| A       | (dispatch_failure, SELF_HEAL, gemini, deep)             | 6 | 5 / 1           | 83%          | PROMOTE          |
| B       | (dispatch_failure, SELF_HEAL, codex, simple)            | 6 | 1 / 5           | 17%          | DEPRECATE        |
| C       | (dispatch_failure, SELF_HEAL, haiku, medium)            | 6 | 3 / 3           | 50%          | IGNORE (mediocre) |
| D       | (budget, ESCALATE_MONTHLY_CAP, none, none)              | 6 | 6 / 0           | 100%         | IGNORE (true-blocker label) |
| E       | (escalation, ARCHITECTURAL_AMBIGUOUS, none, none)       | 6 | 6 / 0           | 100%         | IGNORE (SQL-filtered: `class NOT IN ('escalation','self_improve')`) |

Substrate is **SQLite** (per Phase 2.5 + SUPERSEDES.md), not JSONL. The original PLAN.md text used a `python3 → JSONL heredoc`; SUPERSEDES.md mandates `INSERT INTO decisions` instead. This summary follows SUPERSEDES.md.

## Isolation pattern (mirrors Phase 2 NEW-W-1)

```
TIER9_TMP=$(mktemp -d -t ark-tier9.XXXXXX)
trap "rm -rf '$TIER9_TMP'" EXIT
git init in $TIER9_TMP (so learner_apply_pending can git commit)
ARK_POLICY_DB="$TIER9_TMP/observability/policy.db"   # learner reads/writes this
ARK_HOME="$TIER9_TMP"                                 # digest writes to $ARK_HOME/observability/policy-evolution.md
PENDING_FILE="$TIER9_TMP/observability/policy-evolution-pending.jsonl"
LEARNER_AUTO_APPLY=1                                  # triggers learner_apply_pending → policy.yml + audit + commit
```

Plus a md5 snapshot of `$VAULT_PATH/observability/policy.db` before+after the learner run. Mismatch → check fails. (Confirmed: real vault DB md5 was unchanged.)

## The 20 Tier 9 checks (run order)

| # | Check | Type |
|---|-------|------|
| 1 | `outcome-tagger.sh present`                                                | presence |
| 2 | `policy-learner.sh present`                                                | presence |
| 3 | `policy-digest.sh present`                                                 | presence |
| 4 | `policy-learner.sh syntax valid`                                           | bash -n  |
| 5 | `outcome-tagger.sh syntax valid`                                           | bash -n  |
| 6 | `policy-digest.sh syntax valid`                                            | bash -n  |
| 7 | `ark learn subcommand registered` (grep `^learn)` in scripts/ark)          | wiring   |
| 8 | `ark-deliver post-phase learner trigger present`                           | wiring   |
| 9 | `policy-learner self-test passes`                                          | self-test |
| 10 | `synthetic: 1 promotion in pending sidecar`                               | pipeline |
| 11 | `synthetic: 1 deprecation in pending sidecar`                             | pipeline |
| 12 | `synthetic: zero entries for haiku/medium (mediocre)`                     | pipeline |
| 13 | `synthetic: zero entries for budget/ESCALATE_MONTHLY_CAP (true-blocker)`  | pipeline |
| 14 | `synthetic: zero entries for class:escalation (true-blocker)`             | pipeline |
| 15 | `synthetic: policy.yml gained gemini+codex learned_patterns`              | apply    |
| 16 | `synthetic: digest has Promoted + Deprecated sections`                    | apply    |
| 17 | `synthetic: 2 self_improve audit entries in tmp DB`                       | apply    |
| 18 | `synthetic: tmp vault git gained ≥1 self_improve commit`                  | apply    |
| 19 | `synthetic: real vault policy.db unchanged (isolation guarantee)`         | isolation |
| 20 | `synthetic: idempotent re-run produces no new self_improve entries`       | idempotency |

## Captured output

```
[BLUE] ━━━ Tier 9: Self-improving self-heal ━━━
✅ T9: outcome-tagger.sh present
✅ T9: policy-learner.sh present
✅ T9: policy-digest.sh present
✅ T9: policy-learner.sh syntax valid
✅ T9: outcome-tagger.sh syntax valid
✅ T9: policy-digest.sh syntax valid
✅ T9: ark learn subcommand registered
✅ T9: ark-deliver post-phase learner trigger present
✅ T9: policy-learner self-test passes
✅ T9: synthetic: 1 promotion in pending sidecar
✅ T9: synthetic: 1 deprecation in pending sidecar
✅ T9: synthetic: zero entries for haiku/medium (mediocre)
✅ T9: synthetic: zero entries for budget/ESCALATE_MONTHLY_CAP (true-blocker)
✅ T9: synthetic: zero entries for class:escalation (true-blocker)
✅ T9: synthetic: policy.yml gained gemini+codex learned_patterns
✅ T9: synthetic: digest has Promoted + Deprecated sections
✅ T9: synthetic: 2 self_improve audit entries in tmp DB
✅ T9: synthetic: tmp vault git gained ≥1 self_improve commit
✅ T9: synthetic: real vault policy.db unchanged (isolation guarantee)
✅ T9: synthetic: idempotent re-run produces no new self_improve entries

  Verification: ✅ APPROVED
  20 passed  0 warnings  0 failed  ⏭ 75 skipped
```

## Tier 7 + Tier 8 regression check (no regression)

```
$ bash scripts/ark-verify.sh --tier 7
  13 passed  0 warnings  1 failed  (baseline preserved)
$ bash scripts/ark-verify.sh --tier 8
  24 passed  0 warnings  1 failed  (baseline preserved)
```

The 1 failure each is **pre-existing** and out of scope for this plan:

- **T7 fail:** `T7: execute-phase sources gsd-shape lib` — `scripts/execute-phase.sh` was deleted (renamed to `.HALTED`) and not yet restored. Tracked separately; not introduced by Tier 9.
- **T8 fail:** `T8: Delivery-path scripts source ark-policy.sh` — same root cause (deleted `execute-phase.sh` drops the source-count from 5 to 4).

Both predate this plan. Per the SCOPE BOUNDARY rule (Rule SCOPE BOUNDARY in execute-plan.md), they are logged but not auto-fixed in this plan.

## Acceptance criteria — all met

| Criterion (from PLAN.md) | Status |
| ------------------------ | ------ |
| `bash -n scripts/ark-verify.sh` exits 0                          | ✅ pass |
| `grep -c "Tier 9" scripts/ark-verify.sh` returns >= 4            | ✅ 5    |
| `grep -c "should_run_tier 9" scripts/ark-verify.sh` returns 1+   | ✅ 2    |
| `grep -c 'ARK_HOME="\$TIER9_TMP"' …` returns >= 1                | ✅ 2    |
| `grep -c 'REAL_MD5_BEFORE\|REAL_MD5_AFTER' …` returns >= 2       | ✅ 5    |
| `bash scripts/ark-verify.sh --tier 9` prints 0 fails             | ✅ 20/20 |
| `bash scripts/ark-verify.sh --tier 8` still passes (baseline)    | ✅ 24/25 (baseline) |
| `bash scripts/ark-verify.sh --tier 7` still passes (baseline)    | ✅ 13/14 (baseline) |

## Deviations from Plan

### Auto-fixed

**1. [Rule 3 — Substrate substitution] PLAN.md still referenced JSONL fixture; switched to SQLite INSERTs.**

- **Found during:** initial read of PLAN.md vs SUPERSEDES.md.
- **Issue:** PLAN.md task body shows a `python3 → JSONL heredoc` writing `policy-decisions.jsonl`. Phase 2.5 migrated the substrate to SQLite (`policy.db`); SUPERSEDES.md mandates `INSERT INTO decisions` for synthetic fixtures.
- **Fix:** Used `python3 + sqlite3` to seed the tmp DB directly. md5 isolation check now operates on `policy.db`, not the (now-unused) JSONL log.
- **Files modified:** `scripts/ark-verify.sh` (Tier 9 block).
- **Commit:** `0d8bd5f`.

**2. [Rule 3 — Add policy.yml git-init] policy.yml needs to live in a git repo for `learner_apply_pending` to commit.**

- **Found during:** first dry-run of the synthetic-pipeline check.
- **Issue:** `learner_apply_pending` does `git -C $vault_path commit policy.yml`. If `$TIER9_TMP` isn't a git repo, the commit is silently skipped (graceful degradation). The plan didn't initialise git in the tmp dir, so check 18 would fail.
- **Fix:** Run `git init && git add -A && git commit -m init` in `$TIER9_TMP` before invoking the learner. Subsequent learner commits become the 2nd, 3rd commits — easily counted via `git log --oneline | wc -l`.
- **Files modified:** `scripts/ark-verify.sh`.
- **Commit:** `0d8bd5f`.

**3. [Rule 3 — Stronger pending-file detection] Auto-apply archives the pending sidecar.**

- **Found during:** first dry-run.
- **Issue:** `learner_apply_pending` renames the pending file to `<pending>.applied-<epoch>` after applying. Glob `*.jsonl*` covers both forms.
- **Fix:** Used a glob `$TIER9_TMP/observability/policy-evolution-pending.jsonl*` in `cat | grep -c` checks 10–14.
- **Commit:** `0d8bd5f`.

### Deferred (out of scope per SCOPE BOUNDARY rule)

- **T7 baseline 13/14:** `execute-phase.sh` was deleted upstream (`.HALTED` rename). Restoring or replacing it is the job of a separate plan. Logged.
- **T8 baseline 24/25:** Same root cause as T7 fail (the `source ark-policy.sh` count check expected 5 delivery-path scripts; one is missing).

Both predate this plan; introducing fixes here would dilute the focus of "add Tier 9".

## Self-Check: PASSED

- ✅ `scripts/ark-verify.sh` modified, contains Tier 9 block (20 checks).
- ✅ Commit `0d8bd5f` exists in main.
- ✅ `bash scripts/ark-verify.sh --tier 9` → 20 passed / 0 failed.
- ✅ Tier 7 + Tier 8 unchanged from pre-plan baseline.
- ✅ No new untracked files introduced by this plan (the runtime files at `observability/policy-evolution-pending.jsonl`, `policy-evolution.md`, `policy.db` were already untracked before this plan ran; Tier 9's own writes go to `$TIER9_TMP` which is rm -rf'd on EXIT trap).
