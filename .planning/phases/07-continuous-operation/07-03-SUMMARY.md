---
phase: 07-continuous-operation
plan: 03
subsystem: continuous-operation
tags: [health-monitor, stuck-phase-detection, auto-pause, escalation-dedupe, sentinel-extension, bash3]
requires: ["07-02 (ark-continuous.sh daemon core + sentinels)"]
provides:
  - "continuous_health_monitor — stuck-phase detection across $ARK_PORTFOLIO_ROOT"
  - "continuous_auto_pause_check — 3-failure-tick auto-pause"
  - "STUCK_PHASE_DETECTED + STUCK_ESCALATED + AUTO_PAUSED audit class wiring"
  - "12 new self-test assertions (Tests 16-22, 46/46 total)"
affects:
  - "07-04 (subcommands sentinel still byte-identical — verified by Test 22 md5)"
  - "07-05 (ark dispatcher will see STUCK_PHASE_DETECTED + AUTO_PAUSED rows)"
  - "07-07 (Tier 14 verify can assert stuck-phase escalation chain)"
tech-stack:
  added: []
  patterns:
    - "sentinel-resident function definitions (live entirely between markers; re-defined each tick — bash makes this cheap and globally visible after first call)"
    - "reason-field group key (correlation_id is FK-constrained to decision_id chain in policy.db schema; group key 'stuck:<slug>:<phase>' lives in reason and is queried via LIKE)"
    - "rowid tiebreaker for sub-second TICK_COMPLETE ordering (ts has 1-second resolution; rapid same-second inserts would tie-break arbitrarily)"
    - "no-git-repo treated as 'no recent commits' (last_commit_epoch empty → stuck_git=1) — matches spirit of CONTEXT.md D-CONT-HEALTH"
    - "60-minute consecutive window + 24-hour escalation dedupe (idempotent per CONTEXT.md safety rail #6)"
    - "ARK_PORTFOLIO_ROOT isolated to mktemp-d empty dir BEFORE first tick in self-test (prevents real ~/code projects polluting test DB)"
key-files:
  created: []
  modified:
    - scripts/ark-continuous.sh (314 lines added; 1123 total)
decisions:
  - "Function defs live inside the health-monitor sentinel block (not at top level): honors 07-03's 'edit only between sentinel markers' constraint. Bash defines inner functions globally on first invocation of the wrapper, so after one continuous_tick call both functions are callable from any scope. Re-definition each tick is microsecond-cheap."
  - "Group key encoded in reason, NOT correlation_id: policy.db schema has `correlation_id TEXT REFERENCES decisions(decision_id)` self-FK. Stuffing 'slug:phase' there fails FK constraint. Reason field carries 'stuck:<slug>:<phase> age:NNN' and SQL queries use LIKE to count consecutive detections."
  - "ORDER BY ts DESC, rowid DESC: ts column has 1-second resolution; tests insert TICK_COMPLETE rows within the same second. rowid is SQLite's monotonic insertion counter — guarantees deterministic last-3 selection."
  - "ARK_PORTFOLIO_ROOT export moved to top of self-test (alongside ARK_HOME): the very first continuous_tick call (Test 1) invokes continuous_health_monitor → if portfolio root defaulted to $HOME/code, real Strategix repos would be flagged as stuck and pollute the test DB's STUCK_ESCALATED accounting."
  - "Auto-pause-check dispatches via ark_escalate('repeated-failure', ...) — same class 07-02 used for AUTO_PAUSE_3_FAIL. Architectural-ambiguity reserved for stuck-phase escalations (semantically: a phase that won't progress is an architectural problem, not a runtime failure)."
metrics:
  duration_minutes: 38
  completed: 2026-04-26
  tests_passed: 46
  tests_total: 46
  file_lines: 1123
  lines_added: 314
---

# Phase 7 Plan 07-03: ark-continuous.sh — Health Monitor + Auto-Pause Summary

Health monitor + auto-pause logic shipped inside the 07-02 sentinel: stuck-phase detection across `$ARK_PORTFOLIO_ROOT` (STATE.md mtime > 24h AND no commits in 24h), 3-tick consecutive-detection escalation with 60min window + 24h dedupe, and 3-failure-tick auto-pause. Self-test grew from 34 to 46 assertions (Tests 16-22 added). Real-vault `policy.db` md5 invariant preserved (Test 15 in-suite assertion).

## Files

- **Modified:** `scripts/ark-continuous.sh` (+314 lines: 809 → 1123)

## Function list (added in this plan)

| Function                       | Returns                              | Purpose                                                                                                                                                                                                |
| ------------------------------ | ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `continuous_health_monitor`    | 0 (signals via audit rows)           | Walks `find $ARK_PORTFOLIO_ROOT -maxdepth 3 -path '*/.planning/STATE.md'` (mirrors `portfolio_scan_candidates`). For each project: STATE.md mtime > 24h + no git commit in 24h → log `STUCK_PHASE_DETECTED`. When 3+ detections within 60 min for the same `slug:phase` group key AND no `STUCK_ESCALATED` row in the last 24 h: append ESCALATIONS via `ark_escalate("architectural-ambiguity", …)` and log `STUCK_ESCALATED`. |
| `continuous_auto_pause_check`  | 0 (idempotent; no-op if PAUSE exists)| Inspects last 3 `TICK_COMPLETE` rows ordered by `(ts DESC, rowid DESC)`. If all 3 reasons match GLOB `*f:[1-9]*` (failed count > 0): touch `PAUSE`, log `AUTO_PAUSED`, escalate via `ark_escalate("repeated-failure", …)`. |

Both definitions live inside the `# === SECTION: health-monitor (Plan 07-03) ===` … `# === END SECTION: health-monitor ===` block (inside `continuous_tick`). The block also invokes both functions: `continuous_health_monitor || true` then `continuous_auto_pause_check || true` (non-fatal — business signals are audit rows).

## Audit-class wiring (this plan)

| Decision                | Class       | Wired in        | Reason format                                          |
| ----------------------- | ----------- | --------------- | ------------------------------------------------------ |
| `STUCK_PHASE_DETECTED`  | continuous  | **07-03 (this)**| `stuck:<slug>:<phase> age:<seconds>`                  |
| `STUCK_ESCALATED`       | continuous  | **07-03 (this)**| `stuck:<slug>:<phase> consecutive:<N>`                |
| `AUTO_PAUSED`           | continuous  | **07-03 (this)**| `consecutive_failure_ticks:3`                          |

10 audit classes were wired in 07-02; this plan adds the 3 deferred ones. The remaining `WEEKLY_DIGEST_WRITTEN` belongs to 07-06.

## Detection logic (D-CONT-HEALTH from CONTEXT.md)

1. **Walk portfolio:** `find $ARK_PORTFOLIO_ROOT -maxdepth 3 -type f -name STATE.md -path '*/.planning/STATE.md'`. Default root: `$HOME/code`.
2. **Slug + phase:** `slug=basename(proj_dir)`; `phase=grep -m1 '^current_phase:' STATE.md | sed -E 's/^current_phase:[[:space:]]*//; s/^"//; s/"$//'`.
3. **Stuck-mtime signal:** `(now - stat -f %m STATE.md) > 86400`.
4. **Stuck-git signal:** `git log -1 --format=%ct` empty (no repo or no commits) OR `(now - last_commit_epoch) > 86400`.
5. **Both true → log `STUCK_PHASE_DETECTED`** (reason carries the group key).
6. **Dedupe windows:**
   - **60-minute consecutive window** for counting prior `STUCK_PHASE_DETECTED` rows with the same `stuck:<slug>:<phase>` reason prefix.
   - **24-hour escalation dedupe:** if any `STUCK_ESCALATED` row with the same group key exists in the last 24 h, skip re-escalation.
7. On 3rd detection with no recent escalation → `ark_escalate("architectural-ambiguity", …)` + log `STUCK_ESCALATED`.

## Auto-pause logic (D-CONT-PAUSE safety rail)

- **Idempotent guard:** if `PAUSE` already exists, return 0 immediately.
- **Last-3 tick window** ordered by `(ts DESC, rowid DESC)` — the rowid tiebreaker is required because `ts` has 1-second resolution and rapid same-second `_policy_log` calls would otherwise tie-break arbitrarily.
- **Failure detection:** `reason GLOB '*f:[1-9]*'` matches the `p:N f:M m:K` reason format from 07-02 when `M >= 1`.
- **Action on 3/3 fail:** touch `PAUSE`, log `AUTO_PAUSED`, escalate via `ark_escalate("repeated-failure", …)`.

## Self-test additions (Tests 16-22, 12 new assertions)

| Test | Assertion                                                                       |
| ---- | ------------------------------------------------------------------------------- |
| 16   | Fresh project (STATE.md just touched) → no STUCK row added                      |
| 17   | Stuck project (mtime 25h, no git) → exactly 1 STUCK_PHASE_DETECTED row added    |
| 17a  | Reason field carries `stuck:<slug>:<phase>` group-key prefix                    |
| 18   | 3 invocations within 60 min on same project → ≥3 STUCK_PHASE_DETECTED rows      |
| 18a  | Exactly 1 STUCK_ESCALATED row (the 3rd detection escalates, not earlier)        |
| 18b  | ESCALATIONS.md mentions the project slug                                        |
| 19   | 4th invocation in same window → no new STUCK_ESCALATED (24h dedupe)             |
| 20   | auto_pause_check with last-3 ticks all clean → no PAUSE created                 |
| 21   | auto_pause_check with last-3 ticks all f>0 → PAUSE created                      |
| 21a  | Exactly 1 AUTO_PAUSED row added                                                 |
| 21b  | Re-running with PAUSE present → idempotent (no duplicate AUTO_PAUSED row)       |
| 22   | Subcommands sentinel md5 byte-identical to 07-02 baseline (07-04 area unchanged)|

All 12 use `mktemp -d` portfolio root via `_ct_make_proj` helper. The helper supports three git modes: `fresh` (recent commit), `stale` (commit backdated 48h via `GIT_AUTHOR_DATE` + `GIT_COMMITTER_DATE`), and `none` (no `.git` directory at all).

## Real-vault md5 invariant

```
md5 ~/vaults/ark/observability/policy.db
  baseline (per 07-02): 8cee1b759ff78144da0cc4760995aa6e
  in-suite Test 15 captures md5 BEFORE self-test starts and asserts
  it equals md5 AFTER self-test ends — verified PASS in 46/46 run.
```

External writes to the real DB between self-test invocations (e.g., a stress-test process running on the host) change the on-disk md5 but do not violate the invariant — the invariant is "self-test does not write to real DB", not "real DB is frozen". Test 15 enforces the actual invariant by capturing md5 inside the same process boundary.

## Verification

```
$ bash scripts/ark-continuous.sh --self-test
RESULT: 46/46 pass
✅ ALL ARK-CONTINUOUS CORE TESTS PASSED

$ grep -c 'continuous_health_monitor' scripts/ark-continuous.sh
9                # def + 6 self-test references + sentinel comment + invocation

$ grep -c 'continuous_auto_pause_check' scripts/ark-continuous.sh
7                # def + 4 self-test references + sentinel comment + invocation

$ grep -nE '^[[:space:]]*read[[:space:]]+-p' scripts/ark-continuous.sh
(no matches — pass)

$ awk '/^# === SECTION: subcommands \(Plan 07-04\) ===$/{f=1} f{print} /^# === END SECTION: subcommands ===$/{if(f)exit}' \
    scripts/ark-continuous.sh | md5
2df5ee72a693c4d81ac7bd760a955ab5   # frozen baseline; 07-04 will modify within markers
```

## Constraints honored

- ✅ Bash 3 compat (no `declare -A`, no `mapfile`, no `${var,,}` — verified by Test 14a)
- ✅ Read-only over project files (only writes per-project STATE.md mtime check via `stat`; never touches them)
- ✅ All audit via `_policy_log "continuous" ...` (no inline INSERT)
- ✅ Idempotent: 24h dedupe prevents re-escalation; PAUSE guard prevents duplicate AUTO_PAUSED rows
- ✅ ARK_CREATE_GITHUB unset (test invariant; production daemon never sets it)
- ✅ Sentinel discipline: subcommands section (07-04 area) byte-identical to 07-02 (Test 22)
- ✅ No `read -p` (regression guard Test 14)
- ✅ Self-test runs in mktemp -d isolation (ARK_HOME + ARK_POLICY_DB + ARK_PORTFOLIO_ROOT all redirected)
- ✅ Real ~/vaults/ark/observability/policy.db md5 unchanged across self-test (Test 15)

## Deviations from plan

**[Rule 1 — Bug] Reason field carries the group key, not correlation_id.**
- **Found during:** Initial self-test run (Tests 17-19 all failed).
- **Issue:** The plan's `<action>` block prescribed using `correlation_id` as the slug:phase group key. policy.db schema (`scripts/lib/policy-db.sh:41`) defines `correlation_id TEXT REFERENCES decisions(decision_id)` — a self-FK to the decision_id chain. Inserting `stuck-proj:Phase 7` there fails the FK constraint silently (sqlite returns "FOREIGN KEY constraint failed" but the row is still inserted with NULL correlation_id, OR the entire insert is rejected — either way, group-key queries match nothing).
- **Fix:** Pass `null` as correlation_id; encode the group key in `reason` as `stuck:<slug>:<phase> age:NNN`; query via `reason LIKE 'stuck:<slug>:<phase> %'`. The intent of the plan (idempotent dedupe per project+phase) is preserved.
- **Files modified:** `scripts/ark-continuous.sh` (continuous_health_monitor body; Test 17a updated to check reason instead of correlation_id).

**[Rule 1 — Bug] ORDER BY ts has 1-second resolution; needs rowid tiebreaker.**
- **Found during:** Test 21 failed with last_3_failed=2 instead of 3.
- **Issue:** `ts` column is per-second; rapid same-second TICK_COMPLETE inserts tie-break arbitrarily under `ORDER BY ts DESC LIMIT 3`. SQLite picked an older `f:0` row over a newer `f:1` row.
- **Fix:** `ORDER BY ts DESC, rowid DESC` — rowid is SQLite's monotonic insertion counter.
- **Files modified:** `scripts/ark-continuous.sh` (continuous_auto_pause_check SQL).

**[Rule 1 — Bug] ARK_PORTFOLIO_ROOT must be isolated before the first tick.**
- **Found during:** Tests 18a, 21 failed (real ~/code projects polluting STUCK_ESCALATED count).
- **Issue:** Self-test exported ARK_PORTFOLIO_ROOT only at Test 16 (after Tests 1-15 had already called continuous_tick many times). Each pre-Test-16 tick invoked continuous_health_monitor against the default $HOME/code, writing STUCK_PHASE_DETECTED rows for real Strategix repos into the (isolated) test DB. This polluted the count for later tests but did NOT touch the real DB (Test 15 still passes).
- **Fix:** Export `ARK_PORTFOLIO_ROOT="$TMP/portfolio_isolated_empty"` at the top of self-test alongside ARK_HOME, before any tick runs.
- **Files modified:** `scripts/ark-continuous.sh` (continuous_self_test setup).

**[Rule 2 — Missing critical functionality] Test 22 sentinel md5 needed first-occurrence-only awk pattern.**
- **Found during:** Test 22 fails with the obvious `awk '/pat/,/pat/'` range pattern.
- **Issue:** The self-test code itself contains the marker strings in comments (necessary to document what 07-04 is supposed to fill in). Awk's `/start/,/end/` range matches multiple non-overlapping ranges — so it captures both the real sentinel block AND a fake range over our test code.
- **Fix:** Anchored, first-occurrence-only awk: `/^# === SECTION: subcommands \(Plan 07-04\) ===$/{f=1} f{print} /^# === END SECTION: subcommands ===$/{if(f)exit}`. Baseline md5 captured for the anchored-only output: `2df5ee72a693c4d81ac7bd760a955ab5`.

## Self-Check: PASSED

- [x] `scripts/ark-continuous.sh` modified, 1123 lines (`wc -l` confirmed)
- [x] Self-test passes 46/46 (`bash scripts/ark-continuous.sh --self-test` → "✅ ALL ARK-CONTINUOUS CORE TESTS PASSED")
- [x] `continuous_health_monitor` defined + invoked (grep -c → 9, ≥2 required)
- [x] `continuous_auto_pause_check` defined + invoked (grep -c → 7, ≥2 required)
- [x] No `read -p` invocation (regression guard Test 14)
- [x] Subcommands sentinel byte-identical to 07-02 baseline (Test 22 in-suite assertion)
- [x] STUCK_PHASE_DETECTED + STUCK_ESCALATED + AUTO_PAUSED audit class wiring complete
- [x] 24h escalation dedupe verified (Test 19)
- [x] PAUSE idempotency verified (Test 21b)
- [x] Real-vault `policy.db` md5 unchanged across self-test execution (Test 15)
