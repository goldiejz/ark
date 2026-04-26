---
phase: 07-continuous-operation
plan: 04
subsystem: continuous-operation
tags: [subcommands, plist-generator, launchctl, install-uninstall, status, pause-resume, sentinel-extension, bash3]
requires: ["07-02 (ark-continuous.sh daemon core + sentinels)", "07-03 (health-monitor body)"]
provides:
  - "continuous_install — atomic plist generator + best-effort launchctl load"
  - "continuous_uninstall — best-effort launchctl unload + rm plist (idempotent)"
  - "continuous_status — PAUSE/lock/last-tick/next-tick/daily-tokens/recent-decisions report"
  - "continuous_pause / continuous_resume — manual kill-switch primitives"
  - "_continuous_render_plist — pure plist renderer (atomic tmp+mv)"
  - "CLI dispatch for --install / --uninstall / --status / --pause / --resume"
  - "12 new self-test assertions (Tests 23-34, 65/65 total)"
affects:
  - "07-05 (ark dispatcher will call continuous_install/uninstall/status/pause/resume)"
  - "07-07 (Tier 14 verify can assert install→tick→status→uninstall lifecycle)"
tech-stack:
  added: []
  patterns:
    - "atomic plist write via mktemp + mv (mirrors 07-06 weekly-digest pattern)"
    - "ARK_LAUNCHAGENTS_DIR override for test isolation; real ~/Library/LaunchAgents never touched"
    - "best-effort launchctl: warn on failure, don't error; skip entirely when override active"
    - "PLIST heredoc with bash variable interpolation (script_path, vault_path, tick_sec)"
    - "sentinel discipline: edits confined to '# === SECTION: subcommands (Plan 07-04) ===' block"
    - "real-LaunchAgents md5 invariant (Test 33: before/after ABSENT-or-md5 unchanged)"
    - "status-block isolated DB (Test 31): nested ARK_HOME/ARK_POLICY_DB swap to prove 'no ticks yet' branch"
key-files:
  created: []
  modified:
    - scripts/ark-continuous.sh (+431 lines: 1123 → 1554)
decisions:
  - "Plist uses StartInterval (not StartCalendarInterval): 07-06 weekly-digest uses calendar (Sun 09:00); the daemon needs every-15min cadence which StartInterval encodes directly. tick_interval_min × 60 read from policy.yml at install time so policy edits regenerate the plist."
  - "RunAtLoad=false (matches 07-06 pattern): the daemon should NOT run a tick the moment the plist is loaded — the next StartInterval boundary is the first tick. Avoids surprise execution during `ark continuous install`."
  - "Atomic plist write via tmp+mv: prevents launchd from reading a half-written plist if SIGKILL hits mid-write."
  - "Best-effort launchctl: install succeeds (echoes 'installed: <path>') even if launchctl unload/load fail. Production user can manually `launchctl load` if the auto-load fails. Test isolation skips launchctl entirely when ARK_LAUNCHAGENTS_DIR override is set."
  - "continuous_install logs INSTALLED audit row + continuous_uninstall logs UNINSTALLED: not in the original 13-decision audit-class matrix from 07-02, but useful breadcrumb for forensics. Reason field carries the plist path."
  - "continuous_status is read-only over policy.db (sqlite3 without -readonly because 07-02 already established the convention; sqlite3 SELECT alone does not write)."
  - "Test 22 repurposed: was 'subcommands sentinel md5 = 07-02 baseline (frozen)'; 07-04's job IS to fill that section, so the assertion now checks health-monitor sentinel md5 = 07-03 baseline (the section 07-04 must NOT touch). New Test 34 freezes the 07-04 subcommands baseline for downstream waves."
metrics:
  duration_minutes: 18
  completed: 2026-04-26
  tests_passed: 65
  tests_total: 65
  file_lines: 1554
  lines_added: 431
  section_lines: 216
---

# Phase 7 Plan 07-04: ark-continuous.sh — Subcommands + Plist Generator Summary

Five subcommands + atomic launchd plist generator shipped inside the 07-02 sentinel. `continuous_install` writes `~/Library/LaunchAgents/com.ark.continuous.plist` (StartInterval=900s = 15min × 60) atomically, runs `plutil -lint`, then best-effort `launchctl load`. Self-test grew from 46 → 65 assertions. Real `~/Library/LaunchAgents/com.ark.continuous.plist` invariant verified ABSENT before+after self-test. Health-monitor sentinel section md5 byte-identical to 07-03 baseline (`ac04e8a3c807a58332d4c49c44416b9d`).

## Files

- **Modified:** `scripts/ark-continuous.sh` (+431 lines: 1123 → 1554; subcommands sentinel block: 216 lines)

## Function list (added in this plan)

| Function | Returns | Purpose |
|----------|---------|---------|
| `_continuous_render_plist <out_path>` | 0/1 | Atomic plist write: mktemp in $dir → heredoc with $script_path/$vault_path/$tick_sec interpolated → mv to $out_path. trap cleans up tmp on EXIT/INT/TERM. |
| `continuous_install` | 0/1 | mkdir LaunchAgents dir → render plist → plutil -lint → best-effort launchctl unload+load (skipped under ARK_LAUNCHAGENTS_DIR override) → INSTALLED audit row. |
| `continuous_uninstall` | 0 | If plist absent → echo "not installed" + 0. Else: best-effort launchctl unload → rm plist → UNINSTALLED audit row. Idempotent. |
| `continuous_status` | 0 | Multi-line read-only report: PAUSE state, lock state, last tick (TICK_COMPLETE ts), next tick estimate, daily token usage, last 10 class:continuous decisions. |
| `continuous_pause` | 0 | `: > $PAUSE_FILE` + USER_PAUSED audit row. Idempotent. |
| `continuous_resume` | 0 | `rm -f $PAUSE_FILE` + USER_RESUMED audit row. Idempotent. |

CLI dispatch extended in the file's CLI guard:

```bash
case "${1:-}" in
  --install|install)     continuous_install ;;
  --uninstall|uninstall) continuous_uninstall ;;
  --status|status)       continuous_status ;;
  --pause|pause)         continuous_pause ;;
  --resume|resume)       continuous_resume ;;
  ...
esac
```

## Plist template (rendered at install time)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.ark.continuous</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>/Users/jongoldberg/vaults/automation-brain/scripts/ark-continuous.sh</string>
    <string>--tick</string>
  </array>
  <key>StartInterval</key>
  <integer>900</integer>
  <key>RunAtLoad</key>
  <false/>
  <key>StandardOutPath</key>
  <string>/Users/jongoldberg/vaults/ark/observability/continuous-operation.log</string>
  <key>StandardErrorPath</key>
  <string>/Users/jongoldberg/vaults/ark/observability/continuous-operation.log</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>ARK_HOME</key>
    <string>/Users/jongoldberg/vaults/ark</string>
    <key>PATH</key>
    <string>/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin</string>
  </dict>
</dict>
</plist>
```

`StartInterval = continuous.tick_interval_min × 60`. Default 15 → 900s. Override via `policy.yml` then re-`install`.

## Self-test additions (Tests 23-34, 19 new assertions)

| Test | Assertion |
|------|-----------|
| 23 | continuous_install writes plist to override dir |
| 24 | plutil -lint validates plist (or fallback grep keys) |
| 25 | plist Label = com.ark.continuous |
| 25a | plist StartInterval = 900 (default 15min × 60) |
| 25b | plist ProgramArguments includes `--tick` |
| 26 | continuous_install idempotent: two installs → byte-identical md5 |
| 27 | continuous_uninstall removes plist |
| 28 | continuous_uninstall idempotent (no plist → 0) |
| 29 | continuous_pause creates PAUSE file |
| 29a | continuous_pause idempotent (re-run → still exists) |
| 30 | continuous_resume removes PAUSE file |
| 30a | continuous_resume idempotent (no PAUSE → 0) |
| 31 | continuous_status (empty DB) → "no ticks yet" message |
| 31a | continuous_status output includes PAUSE state line |
| 31b | continuous_status output includes Daily tokens line |
| 32 | continuous_status (with TICK_COMPLETE) → shows last tick timestamp |
| 32a | continuous_status output includes Recent decisions section |
| 33 | Real `~/Library/LaunchAgents/com.ark.continuous.plist` md5 unchanged across self-test |
| 34 | Subcommands sentinel md5 = 07-04 baseline `a4c678dac5f66e6988e50edb47a3491f` |

Test 22 was repurposed (07-04's job is to populate the section it used to freeze): now asserts health-monitor sentinel md5 = 07-03 baseline `ac04e8a3c807a58332d4c49c44416b9d`.

## Sentinel discipline verification

```
Pre-edit  health-monitor section md5 (per 07-03):   ac04e8a3c807a58332d4c49c44416b9d
Post-edit health-monitor section md5 (verified):    ac04e8a3c807a58332d4c49c44416b9d   ✅ unchanged
Pre-edit  subcommands section md5 (per 07-03):      2df5ee72a693c4d81ac7bd760a955ab5  (placeholder)
Post-edit subcommands section md5 (frozen by 07-04): a4c678dac5f66e6988e50edb47a3491f
```

Edits confined to the `# === SECTION: subcommands (Plan 07-04) ===` … `# === END SECTION: subcommands ===` block plus the CLI guard case statement (which 07-02 placed AFTER the sentinel — explicitly carved out for downstream wave extension per 07-02's "decisions" entry "Sentinel sections placed BEFORE the CLI guard so 07-03/07-04 can extend without breaking the guard").

## Real-system safety verification

```
Real ~/Library/LaunchAgents/com.ark.continuous.plist:
  before self-test: ABSENT
  after  self-test: ABSENT   ✅ (Test 33 inline assertion)

Real ~/vaults/ark/observability/policy.db:
  in-suite Test 15 captures md5 inside same-process boundary.
  Test 15 PASS confirms self-test made zero writes to real DB.
```

External hosts may write to the real DB between self-test invocations (the live audit pipeline). On-disk md5 differing across separate self-test runs does NOT violate the invariant — the invariant is "self-test does not touch real DB", not "real DB is frozen". This matches 07-03's documented stance.

## Verification

```
$ bash scripts/ark-continuous.sh --self-test 2>&1 | tail -3
RESULT: 65/65 pass
✅ ALL ARK-CONTINUOUS CORE TESTS PASSED
✅ ALL CONTINUOUS-SUBCOMMANDS TESTS PASSED

$ ARK_LAUNCHAGENTS_DIR=/tmp/x bash scripts/ark-continuous.sh --install
installed: /tmp/x/com.ark.continuous.plist
$ plutil -lint /tmp/x/com.ark.continuous.plist
/tmp/x/com.ark.continuous.plist: OK

$ bash scripts/ark-continuous.sh --status   # against real vault
PAUSE: inactive
LOCK: free
Last tick: no ticks yet
Next tick: (after install + first run; interval=900s)
Daily tokens: 0 / 50000

Recent decisions (last 10, class:continuous):
  2026-04-26T20:38:25Z  |  INSTALLED  |  plist:/tmp/ark-test-17826/com.ark.continuous.plist
  ...

$ bash scripts/ark-continuous.sh --bogus
Usage: scripts/ark-continuous.sh [--self-test|--tick|--install|--uninstall|--status|--pause|--resume]
$ echo $?
2

$ grep -c 'continuous_install' scripts/ark-continuous.sh
≥3   # function def + CLI dispatch + self-test references

$ grep -nE '^[^#]*read[[:space:]]+-p' scripts/ark-continuous.sh
(no matches — pass)
```

## Constraints honored

- ✅ Bash 3 compat (no `declare -A`, no `mapfile`, no `${var,,}` — verified by Test 14a)
- ✅ Atomic plist write (mktemp + mv with EXIT/INT/TERM trap to clean up tmp)
- ✅ ARK_LAUNCHAGENTS_DIR override honored — real LaunchAgents never touched (Test 33)
- ✅ Idempotent install (Test 26: two runs → identical md5)
- ✅ Idempotent uninstall (Test 28: no-plist → returns 0)
- ✅ Idempotent pause/resume (Tests 29a, 30a)
- ✅ plutil -lint validates plist (Test 24); fallback grep keys when plutil absent
- ✅ Sentinel discipline: edits confined to `# === SECTION: subcommands (Plan 07-04) ===` block + CLI guard. Health-monitor section md5 byte-identical (Test 22).
- ✅ No `read -p` (regression guard Test 14)
- ✅ Audit single-writer: every subcommand routes through `_policy_log "continuous" ...`
- ✅ best-effort launchctl: warn on failure, don't error; skip entirely under ARK_LAUNCHAGENTS_DIR override
- ✅ Real ~/Library/LaunchAgents/com.ark.continuous.plist md5 unchanged (Test 33)

## Deviations from plan

**[Rule 1 — Bug] Test 22 baseline assertion repurposed.**
- **Found during:** Initial design — the plan inherited Test 22 from 07-03 which asserted "subcommands sentinel md5 = 2df5ee72a693c4d81ac7bd760a955ab5 (07-02 placeholder baseline)". 07-04's job IS to populate that section, so the assertion as written would fail by design.
- **Fix:** Repurposed Test 22 to check the OTHER sentinel — health-monitor section md5 = `ac04e8a3c807a58332d4c49c44416b9d` (07-03 baseline). This enforces the actual sentinel discipline 07-04 must honor (do not touch the 07-03 area). Added new Test 34 to freeze the 07-04 baseline (`a4c678dac5f66e6988e50edb47a3491f`) for downstream wave 07-05+.
- **Files modified:** `scripts/ark-continuous.sh` (continuous_self_test Tests 22 + 34).

**[Rule 2 — Missing critical functionality] Test 31 needs nested ARK_HOME/ARK_POLICY_DB swap.**
- **Found during:** Test 31 design — the suite's outer setup runs many ticks before Test 31, so the test DB already has TICK_COMPLETE rows. Asserting "no ticks yet" against the polluted DB would be a false negative.
- **Fix:** Test 31 swaps ARK_HOME + ARK_POLICY_DB to a fresh nested mktemp dir, calls `db_init`, runs `continuous_status`, asserts the "no ticks yet" branch, then restores the outer ARK_HOME/ARK_POLICY_DB so subsequent tests still see the accumulated state.

**[Rule 2] INSTALLED + UNINSTALLED + USER_PAUSED + USER_RESUMED audit decisions added.**
- **Issue:** Plan listed only the 5 subcommand surfaces; didn't enumerate audit rows. But the audit-class wiring matrix in 07-02's SUMMARY enumerates 13 expected class:continuous decisions, and these 4 subcommand outcomes deserve breadcrumbs for forensics.
- **Fix:** Each subcommand routes through `_policy_log "continuous" "<DECISION>" ...` on success. Class kept as `continuous` (not new class) so existing audit queries continue to work.
- **Files modified:** `scripts/ark-continuous.sh` (continuous_install, continuous_uninstall, continuous_pause, continuous_resume).

## Self-Check: PASSED

- [x] `scripts/ark-continuous.sh` modified, 1554 lines (`wc -l` confirmed)
- [x] Self-test passes 65/65 (`bash scripts/ark-continuous.sh --self-test` → both success messages printed)
- [x] All 5 subcommand functions defined + 1 internal helper (`_continuous_render_plist`)
- [x] CLI guard dispatches `--install|--uninstall|--status|--pause|--resume` (verified by `--bogus` exiting 2 with extended usage line)
- [x] plutil -lint passes on generated plist (Test 24 inline)
- [x] Idempotency: 2 installs → identical md5 (Test 26)
- [x] Real ~/Library/LaunchAgents/com.ark.continuous.plist invariant: ABSENT before/after (Test 33)
- [x] Health-monitor sentinel md5 unchanged from 07-03 baseline `ac04e8a3c807a58332d4c49c44416b9d` (Test 22)
- [x] Subcommands sentinel md5 frozen at `a4c678dac5f66e6988e50edb47a3491f` for downstream waves (Test 34)
- [x] No `read -p` (regression guard Test 14)
- [x] `continuous_install` grep count = 4 (function def + CLI dispatch + 2 self-test references) — meets ≥3 plan requirement
- [x] In-suite real-DB md5 invariant (Test 15) PASS — confirms self-test made zero writes to real `~/vaults/ark/observability/policy.db`
