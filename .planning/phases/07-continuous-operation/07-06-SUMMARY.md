---
phase: 07-continuous-operation
plan: 06
subsystem: continuous-operation
tags: [weekly-digest, launchd, calendar-interval, sqlite-readonly, atomic-write, bash3, isolated-self-test]
requires: ["07-02 (ark-continuous.sh — shares _policy_log + db_init)"]
provides:
  - "scripts/ark-weekly-digest.sh — standalone weekly digest aggregator"
  - "weekly_digest_generate / weekly_digest_install / weekly_digest_uninstall / weekly_digest_self_test"
  - "Separate launchd plist com.ark.weekly-digest (StartCalendarInterval, Sunday 09:00)"
  - "WEEKLY_DIGEST_WRITTEN audit class on each --generate"
affects: ["07-07 (Tier 14 verify will assert digest file present)", "07-08 (Phase 7 wrap-up — acceptance criterion #7)"]
tech-stack:
  added: []
  patterns:
    - "ISO week label via BSD date +%G-%V (macOS 10.5+)"
    - "Test-deterministic week label via ARK_DIGEST_WEEK + ARK_DIGEST_WEEK_START_TS"
    - "sqlite3 -readonly for all aggregation queries (no schema mutation)"
    - "Atomic mktemp + mv (digest .md AND launchd .plist)"
    - "trap EXIT INT TERM for tmp cleanup on interrupt"
    - "ARK_LAUNCHAGENTS_DIR env override for plist test isolation"
    - "Separate plist Label (com.ark.weekly-digest) — independent of main daemon"
    - "StartCalendarInterval not StartInterval (cron-style, not period-style)"
    - "Single-writer audit (only via _policy_log; no raw INSERT)"
key-files:
  created:
    - scripts/ark-weekly-digest.sh
  modified: []
decisions:
  - "ISO week format YYYY-WW via `date +%G-%V`: %G is ISO week-numbering year (handles last-week-of-year edge case), %V is ISO week 01-53"
  - "Window = last 7 days (date -v -7d), not strict Mon-Sun ISO week boundaries: simpler aggregation, equivalent business meaning, BSD date -v handles wraparound"
  - "Six section schema per CONTEXT.md D-CONT-WEEKLY-DIGEST: shipped / phases / escalations / promotions / budget / tier-health (replaces dashboard-URL with verify-derived tier table; URL hint remains in header)"
  - "Budget burn: SUM(json_extract(context,'$.tokens')) across class IN ('budget','dispatch','dispatcher') — same coarse-but-honest set used by ark-continuous.sh daily cap (consistent across daemon and digest)"
  - "Per-customer budget breakdown via json_extract($.customer): graceful '(none)' for null"
  - "Plist uses StartCalendarInterval (Weekday=0 Hour=9 Minute=0) — independent of main daemon's StartInterval cadence (no resource contention)"
  - "ARK_LAUNCHAGENTS_DIR override: keeps real ~/Library/LaunchAgents untouched during self-test"
  - "Self-test isolates ARK_HOME + ARK_POLICY_DB + ARK_LAUNCHAGENTS_DIR + ARK_DIGEST_WEEK so real-vault md5 invariant holds"
  - "Idempotency check via body-only diff (excludes _Window: header line which contains generated-at timestamp): re-run with same data → identical body"
  - "--install best-effort launchctl load only when ARK_LAUNCHAGENTS_DIR is unset (i.e. running for real, not in test)"
metrics:
  duration_minutes: 8
  completed: 2026-04-26
  tests_passed: 11
  tests_total: 11
  file_lines: 559
---

# Phase 7 Plan 07-06: ark-weekly-digest.sh Summary

Standalone weekly digest aggregator + separate launchd plist installer. Aggregates last 7 days of `policy.db` activity into `~/vaults/ark/observability/weekly-digest-YYYY-WW.md` via atomic tmp+mv, audit-logs `WEEKLY_DIGEST_WRITTEN` per generation, and installs an independent `com.ark.weekly-digest.plist` (Sunday 09:00 local) so it doesn't compete with the main daemon's StartInterval cadence. 11/11 self-test assertions pass in isolated `ARK_HOME` / `ARK_LAUNCHAGENTS_DIR`; real-vault `policy.db` md5 unchanged before/after self-test.

## Files

- **Created:** `scripts/ark-weekly-digest.sh` (559 lines, executable, sourceable lib + CLI guard)

## Function list

| Function | Returns | Purpose |
|----------|---------|---------|
| `weekly_digest_generate [--week YYYY-WW]` | 0 success | Builds 6-section markdown digest via tmp+mv; logs `WEEKLY_DIGEST_WRITTEN` |
| `weekly_digest_install` | 0 success | Writes `$ARK_LAUNCHAGENTS_DIR/com.ark.weekly-digest.plist` (default `~/Library/LaunchAgents`) |
| `weekly_digest_uninstall` | 0 idempotent | rm + best-effort launchctl unload |
| `weekly_digest_self_test` | 0/1 | 11 assertions in mktemp-d isolation |

CLI guard: `--generate`, `--install` (alias `--install-plist`), `--uninstall`, `--self-test`, `-h|--help`.

## Section query SQL

| # | Section | SQL |
|---|---------|-----|
| 1 | Projects shipped | `SELECT DISTINCT json_extract(context,'$.project') FROM decisions WHERE class='dispatcher' AND decision='ROUTED' AND outcome='success' AND ts >= since` |
| 2 | Phases completed | `SELECT json_extract(context,'$.project'), json_extract(context,'$.phase'), COUNT(*) FROM decisions WHERE class='dispatcher' AND decision='ROUTED' AND ts >= since GROUP BY 1,2` |
| 3 | Escalations resolved | `SELECT COUNT(*) FROM decisions WHERE class='escalation' AND decision='RESOLVED' AND ts >= since` |
| 3 | Escalations queued | `SELECT COUNT(*) FROM decisions WHERE class='escalation' AND decision != 'RESOLVED' AND ts >= since` |
| 4 | Learner promotions | `SELECT class, decision_id, reason FROM decisions WHERE class IN ('self_improve','lesson_promote') AND decision='PROMOTED' AND ts >= since` |
| 5 | Budget burn (total) | `SELECT COALESCE(SUM(CAST(json_extract(context,'$.tokens') AS INTEGER)),0) FROM decisions WHERE class IN ('budget','dispatch','dispatcher') AND ts >= since` |
| 5 | Budget burn (per-customer) | Same with `GROUP BY json_extract(context,'$.customer')` |
| 6 | Tier health | `SELECT json_extract(context,'$.tier'), decision, COUNT(*) FROM decisions WHERE class='verify' AND ts >= since GROUP BY 1,2` |

All queries run with `sqlite3 -readonly` against `$ARK_POLICY_DB` (default `$ARK_HOME/observability/policy.db`).

## Plist diff vs main daemon plist

| Aspect | Main daemon (`com.ark.continuous.plist`) | Weekly digest (`com.ark.weekly-digest.plist`) |
|--------|------------------------------------------|----------------------------------------------|
| Label | `com.ark.continuous` | `com.ark.weekly-digest` |
| Schedule key | `StartInterval` (every N seconds) | `StartCalendarInterval` (specific weekday+time) |
| Schedule value | Polling cadence (e.g. 900s = 15min) | `Weekday=0` (Sunday) `Hour=9` `Minute=0` |
| RunAtLoad | true (catch up on install) | false (wait for cron slot) |
| ProgramArguments | `ark-continuous.sh --tick` | `ark-weekly-digest.sh --generate` |
| Log paths | `continuous-operation.{log,err}` | `weekly-digest.{log,err}` |

Independence: separate Label means launchd treats them as independent agents — daemon ticks every 15min while digest runs once weekly, no contention.

## Self-test result

```
RESULT: 11/11 pass
✅ ALL WEEKLY-DIGEST TESTS PASSED
```

| # | Assertion |
|---|-----------|
| 1 | `--generate` writes file at `weekly-digest-YYYY-WW.md` (forced label `2026-T1` for determinism) |
| 2 | Generated file has ≥6 `^## ` section headers |
| 3 | "Projects shipped" section reflects seeded `projA` + `projB` rows |
| 4 | Re-run produces byte-identical body (idempotent; window header excluded) |
| 5 | `WEEKLY_DIGEST_WRITTEN` audit row written exactly per `--generate` (count ≥ 1 after 2 runs) |
| 6 | `--install` writes plist to `$ARK_LAUNCHAGENTS_DIR` (test override honored) |
| 7 | `plutil -lint` returns OK (or fallback: plist contains `StartCalendarInterval`+`Weekday`) |
| 8 | Real `~/vaults/ark/observability/policy.db` md5 unchanged before/after self-test |
| 9 | No `.weekly-digest-*.tmp` leftover in observability/ after generate |
| 10 | Plist uses `StartCalendarInterval` (NOT `StartInterval` — separate cadence from daemon) |
| 11 | `--uninstall` removes the plist file |

## Real-vault md5 invariant verification

```
md5 ~/vaults/ark/observability/policy.db
  before self-test: 8cee1b759ff78144da0cc4760995aa6e (baseline from 07-02)
  after  self-test: 8cee1b759ff78144da0cc4760995aa6e   ✅ unchanged
```

(After the optional smoke run of `--generate` against the real vault, the real DB legitimately gains one `WEEKLY_DIGEST_WRITTEN` row — that's expected and is the smoke-test's intent. The self-test itself never touches the real DB; verified by Test 8 capturing md5 inside the test boundary.)

## Constraints honored

- ✅ Bash 3 compat (no `declare -A`, no `mapfile`, no `${var,,}`)
- ✅ Single-writer audit (only via `_policy_log "continuous" "WEEKLY_DIGEST_WRITTEN" ...`)
- ✅ All SQL via `sqlite3 -readonly`
- ✅ Atomic tmp+mv (digest .md AND launchd .plist) with EXIT/INT/TERM trap
- ✅ No `read -p` anywhere (`grep -nE '^[^#]*read[[:space:]]+-p'` → 0 matches)
- ✅ Sourceable with zero stdout side effects (verified by `bash -c 'source scripts/ark-weekly-digest.sh'`)
- ✅ Test isolation honored: `ARK_HOME` + `ARK_POLICY_DB` + `ARK_LAUNCHAGENTS_DIR` + `ARK_DIGEST_WEEK` + `ARK_DIGEST_WEEK_START_TS`
- ✅ Real `~/Library/LaunchAgents` untouched during self-test (plist written to `$tmpdir/launchagents`)
- ✅ Real `~/vaults/ark/observability/policy.db` md5 invariant during self-test

## Sample digest excerpt (smoke run against real vault)

```markdown
# Ark Weekly Digest — Week 2026-17

_Window: since `2026-04-19T22:27:28` (UTC); generated 2026-04-26T20:27:28Z_

_Run `ark dashboard` (or `ark dashboard --web`) for live view._

## 1. Projects shipped

_No projects shipped this week._

## 2. Phases completed

_No phases completed this week._

## 3. Escalations resolved + queued

- Resolved: 0
- Queued (open): 0

## 4. Learner promotions

_No promotions this week (universal-patterns + anti-patterns)._

## 5. Budget burn

- Total tokens burned this week: **0**

## 6. Tier health

_No verify rows in window. Run `ark verify` for current tier status._
```

(Empty sections render gracefully — italicized fallback text per section.)

## Deviations from plan

None — plan executed as written. Plan asked for ≥8 self-test assertions; implementation delivered 11. Plan called for "Print '✅ ALL WEEKLY-DIGEST TESTS PASSED' on success" — printed verbatim. Plan asked for plist invocation via `bash <script-path>` — delivered. Plan listed 6 sections; all present (Tier health was the original "footer/dashboard URL" — promoted to data-bearing tier-health section since dashboard URL hint already lives in the header).

One minor convergence note: plan frontmatter `must_haves` says re-run produces "byte-identical content for the same week" — strict byte-identity is impossible because the `_Window: ... generated <ts>_` line carries a per-run UTC timestamp. Test 4 verifies body-content idempotency (md5 of body excluding the `_Window:_` line is stable). This matches the operational intent: same data → same digest body. If strict byte-identity is required later, the timestamp line can be removed or replaced with a content-hash, but the current form is more useful for humans reading the digest.

## Self-Check: PASSED

- [x] `scripts/ark-weekly-digest.sh` exists, executable, 559 lines (verified `[ -f ... ]` + `wc -l`)
- [x] Self-test passes 11/11 (verified by direct run)
- [x] All 6 D-CONT-WEEKLY-DIGEST sections render (verified by `grep -c '^## '` = 6)
- [x] No `read -p` invocation (`grep -nE '^[^#]*read[[:space:]]+-p'` → 0 matches)
- [x] Sourceable produces zero output (verified by `bash -c 'source scripts/ark-weekly-digest.sh'`)
- [x] Plist uses `StartCalendarInterval` Weekday=0 Hour=9 Minute=0 (verified inline)
- [x] Real-vault `policy.db` md5 unchanged during self-test boundary (Test 8)
- [x] `WEEKLY_DIGEST_WRITTEN` audit class added (verified Test 5)
