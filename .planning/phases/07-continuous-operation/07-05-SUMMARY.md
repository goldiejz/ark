---
phase: 07-continuous-operation
plan: 05
subsystem: ark-dispatcher
tags: [dispatcher, wiring, continuous, phase-7]
requires: [07-04]
provides: [ark-continuous-dispatch]
affects: [scripts/ark]
tech-stack:
  added: []
  patterns: [pure-passthrough-dispatcher, exit-code-propagation]
key-files:
  created: []
  modified: [scripts/ark]
decisions:
  - "Pure pass-through: zero business logic in cmd_continuous; mirrors dashboard/promote-lessons arms"
  - "Help text routed to stderr + return 2 (matches '--help' convention for missing-subarg invocations)"
  - "Existence check on ark-continuous.sh before dispatch — friendly error if Phase 7 not installed"
metrics:
  duration: "~10min"
  tasks_completed: 1
  files_modified: 1
  loc_added: 53
  loc_removed: 0
completed_date: 2026-04-26
---

# Phase 7 Plan 07-05: ark dispatcher continuous wiring Summary

Wired `ark continuous <subcmd>` into `scripts/ark` as a pure pass-through to `scripts/ark-continuous.sh` — six subcommands (install, uninstall, status, pause, resume, tick) plus help text, with an existence-check guard for graceful failure when Phase 7 isn't installed.

## Implementation

Added in `scripts/ark`:

1. **`cmd_continuous()` function** (after `cmd_align`, before `cmd_create`). Pattern mirrors `ark dashboard` and `ark promote-lessons` arms:
   - Existence check on `$VAULT_PATH/scripts/ark-continuous.sh` → exit 1 with friendly message if missing.
   - `case "$sub"` dispatching each subcommand to `bash $VAULT_PATH/scripts/ark-continuous.sh --<flag> "$@"`.
   - Help arm (`""|help|-h|--help`) prints usage to stderr listing all 6 subcommands, INBOX format, and env vars; returns exit 2.
   - Default arm prints `unknown subcommand: <name>` to stderr; returns exit 2.

2. **Case-statement entry** added between `observe` and `context` arms:
   ```bash
   continuous) shift; cmd_continuous "$@" ;;
   ```

3. **Help-text update** in `cmd_help` heredoc — `continuous` listed under `HEALTH & MAINTENANCE` block (alongside `observe`), with one-liner pointing to `ark continuous --help` for full subcommand usage + INBOX format.

## Diff Profile

```
 scripts/ark | 53 +++++++++++++++++++++++++++++++++++++++++++++++++++++
 1 file changed, 53 insertions(+)
```

**Strictly additive** — no removals, no modifications to existing arms or functions. Verified via `git diff --stat`.

## Smoke-Test Results

| Test | Result |
|------|--------|
| `bash -n scripts/ark` | SYNTAX OK |
| `ark continuous --help` | exit 2; lists 6 subcommands + INBOX format |
| `ark continuous` (no subarg) | exit 2; same usage text |
| `ark continuous bogus-cmd` | exit 2; "unknown subcommand: bogus-cmd" |
| `ark continuous status` | exit 0; passes through, prints PAUSE/LOCK/last-tick/decisions |
| `ark continuous pause` → `resume` | exit 0/0; PAUSE file created then removed |
| `ark help \| grep continuous` | matches (line 209-211 in cmd_help heredoc) |
| `grep -c "continuous" scripts/ark` | 16 (well above ≥3 threshold) |
| Regression: `ark dashboard --help` | exit 0 (unchanged) |
| Regression: `ark help` | exit 0 (unchanged) |
| Regression: `ark escalations --help` | exit 0 (unchanged) |

## Backward Compatibility

- Zero modifications to existing `cmd_*` functions or case arms.
- New case arm placed between `observe` and `context` — does not shadow any existing pattern.
- `VAULT_PATH` already defined at top of script (line 19); reused, not redefined.
- Subshell exit codes propagate naturally (Bash default); no `|| true` wrapping.
- Bash 3 compatible: only uses `local`, `case`, `cat <<EOF`, `[[`, `${1:-}` — all Bash 3+.

## Help-Text Excerpt

```
ark help | grep -A2 continuous
    continuous  Continuous-operation agent (launchd-driven). Subcommands:
                  install | uninstall | status | pause | resume | tick
                  Run 'ark continuous --help' for full usage + INBOX format.

ark continuous --help
usage: ark continuous <subcommand>

Subcommands:
  install     generate + load ~/Library/LaunchAgents/com.ark.continuous.plist
  uninstall   unload + remove the launchd agent + plist
  status      show last tick / next tick / recent decisions / daily tokens
  pause       create PAUSE file (kill-switch — agent skips ticks while present)
  resume      remove PAUSE file (resume scheduled ticks)
  tick        run one tick manually (for debugging)

INBOX:
  Drop tasks into ~/vaults/ark/INBOX/ as plain-text or markdown files.
  Each tick scans the INBOX, dispatches work, and archives processed items.

Environment:
  ARK_LAUNCHAGENTS_DIR  Override LaunchAgents dir (test isolation)
  ARK_HOME              Override vault path (default: ~/vaults/ark)
```

## Deviations from Plan

None. Plan executed as written. Minor enhancements within scope:
- Added existence-check guard on `scripts/ark-continuous.sh` (mirrors how `ark promote-lessons` and `ark dashboard` arms guard against missing dependencies — Rule 2: defensive correctness, consistent with existing dispatcher patterns).
- Added `INBOX:` and `Environment:` sections to the `--help` output to satisfy plan requirement "describe purpose + INBOX file format".

## Success Criteria

- [x] 6 subcommands dispatch to correct `ark-continuous.sh` flags
- [x] Help text reflects new arm (cmd_help heredoc + dedicated `--help` block)
- [x] No regression in existing dispatcher arms (spot-checked dashboard, escalations, help)
- [x] Diff is additive-only (53 insertions, 0 removals)
- [x] Bash 3 compatible
- [x] No `read -p`, no business logic in dispatcher

## Self-Check: PASSED

- scripts/ark: FOUND (modified, 53 insertions)
- .planning/phases/07-continuous-operation/07-05-SUMMARY.md: FOUND (this file)
- Commit: pending (next step)
