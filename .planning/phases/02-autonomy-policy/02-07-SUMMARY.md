---
phase: 02-autonomy-policy
plan: 07
subsystem: autonomy-audit
tags: [audit, observer, autonomy, manual-gate]
requires: [02-03, 02-04, 02-05, 02-06, 02-06b]
provides:
  - "Final delivery-path audit clean (zero unintentional read -[pr])"
  - "Observer pattern manual-gate-hit (regression detector)"
affects:
  - scripts/ark-team.sh
  - observability/observer/patterns.json
tech-stack:
  added: []
  patterns: [observer-regex-detection, intentional-gate-tagging]
key-files:
  created: []
  modified:
    - scripts/ark-team.sh
    - observability/observer/patterns.json
decisions:
  - "Use Python-compatible \\s+ in pattern regex (observer uses re.search not grep -E)"
  - "ark-team.sh:196 stream-parser tagged as intentional gate (not user prompt)"
  - "ark-observer.sh untagged read calls excluded from audit scope (observer is not a delivery-path script per plan)"
metrics:
  duration: ~3min
  completed: 2026-04-26
---

# Phase 2 Plan 02-07: Final Audit + Observer manual-gate-hit Summary

Final autonomy audit of delivery-path scripts and addition of an observer pattern that catches any future regression of manual interactive gates on the autonomous delivery path.

## Tasks Completed

### Task 1: Final delivery-path audit

Ran:

```
grep -rEn 'read -[pr]|read.*PROMPT|read.*"[YyNn]"' \
  scripts/ark-deliver.sh scripts/ark-team.sh scripts/execute-phase.sh \
  scripts/ark-budget.sh scripts/self-heal.sh
```

**Pre-fix matches (4):**
- `scripts/ark-deliver.sh:263` — already tagged `# AOS: intentional gate (loop iterator over heredoc, not user-input prompt)`
- `scripts/ark-team.sh:196` — **untagged** stream parser (`while IFS= read -r _pf` over `gsd_find_plan_files` heredoc output) → fixed
- `scripts/execute-phase.sh:143` — already tagged `# AOS: intentional gate — stream parsing, not stdin`
- `scripts/execute-phase.sh:608` — already tagged `# AOS: intentional gate — stream parsing, not stdin`

**Fix applied:** Tagged ark-team.sh:196 with `# AOS: intentional gate — stream parsing, not stdin`.

**Post-fix audit:** Zero unintentional matches.

```
$ grep -rEn 'read -[pr]|read.*PROMPT' scripts/ark-deliver.sh scripts/ark-team.sh \
    scripts/execute-phase.sh scripts/ark-budget.sh scripts/self-heal.sh \
  | grep -v 'AOS: intentional gate'
(no output)
```

**Commit:** `1b0fdb6`

### Task 2: Observer pattern manual-gate-hit

Appended to `observability/observer/patterns.json`:

```json
{
  "id": "manual-gate-hit",
  "regex": "(read\\s+-[pr]\\b|press\\s+any\\s+key|continue\\?|\\(y/N\\)|\\(Y/n\\))",
  "regex_flags": "i",
  "category": "logic-bug",
  "severity": "critical",
  "lesson_after_n": 1,
  "auto_fix": "log-only",
  "description": "Autonomous-path script hit interactive prompt — autonomy regression. Phase 2 banned manual gates in delivery-path scripts; any new occurrence must route through policy_* or ark_escalate.",
  "tail_targets": [
    ".planning/delivery-logs/*.log",
    "$ARK_HOME/observability/dispatch-logs/*.log"
  ],
  "created_phase": "02-autonomy-policy"
}
```

**Note on regex syntax:** Plan 02-07 originally specified `[[:space:]]+`. During TDD verification we discovered the observer (`scripts/ark-observer.sh:204`) consumes patterns via Python `re.search`, which does not honor POSIX bracket classes. Switched to `\s+` (Python-compatible, also valid in PCRE/JS engines if patterns are ever ported). Smoke-tested via `python3 -c "import re; ..."` against 6 positive and 3 negative samples — all pass.

**Commit:** `b35e7c3`

### Task 3: Wording cleanup (NEW-W-5)

Searched `.planning/phases/02-autonomy-policy/` and `scripts/` for the legacy phrase "MUST be empty" referring to the `read -p` audit. **No occurrences found.** The canonical phrasing already in use across 02-07-PLAN.md and 02-06b-PLAN.md is "zero matches except lines tagged `# AOS: intentional gate`" — already correct. No-op for this codebase.

## Verification

| Check | Command | Result |
|---|---|---|
| Audit clean | `grep -rEn 'read -[pr]\|read.*PROMPT' <5 scripts> \| grep -v 'AOS: intentional gate'` | 0 lines (CLEAN) |
| Bash syntax | `bash -n scripts/ark-team.sh` | OK |
| JSON valid | `python3 -c "import json; json.load(open('observability/observer/patterns.json'))"` | OK |
| Pattern present | id `manual-gate-hit` in patterns array | present (15th entry) |
| Regex positive | `read -p`, `press any key`, `Continue?`, `(y/N)`, `(Y/n)`, `read -r` | all 6 match |
| Regex negative | `echo hello world`, `just normal text` | no match |

## Pattern count reconciliation

Plan estimated 14 (Phase 1) + 4 GSD additions + 1 (manual-gate-hit) = 19. Actual on-disk count before this plan: **14** (Phase 1 GSD-blindness patterns were already merged into the original 14 — patterns `gsd-multi-plan-missed`, `gsd-phase-dir-collision`, `empty-plan-dispatched`, `phase-dir-creation-without-tasks` are the GSD additions, already counted). After 02-07: **15 patterns total**. The plan's arithmetic assumed pre-merge state; the on-disk count was already consolidated.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] POSIX bracket class incompatible with Python re engine**
- **Found during:** Task 2 verification (smoke test)
- **Issue:** Plan-specified regex used `[[:space:]]+` which Python's `re` module does not interpret as a whitespace class — it treats it as a character class containing the literal characters `:`, `s`, `p`, `a`, `c`, `e`. The observer at `scripts/ark-observer.sh:204` uses `re.search`, so the original pattern would not have matched real `read -p` lines (only literal substrings like `read[a-z:]+-p`).
- **Fix:** Changed `[[:space:]]+` → `\s+` (Python `\s` is the standard whitespace shortcut). Also added `\b` word boundary after `-[pr]` to prevent over-matching tokens like `-print`.
- **Files modified:** `observability/observer/patterns.json`
- **Commit:** `b35e7c3`

### Auth Gates

None.

### Architectural Changes

None.

## Files Modified

- `scripts/ark-team.sh` (1 line: added intentional-gate tag at line 196)
- `observability/observer/patterns.json` (+15 lines: new pattern entry)

## Commits

| Hash | Message |
|---|---|
| `1b0fdb6` | Phase 2 Plan 02-07: tag ark-team.sh stream-parser read as intentional gate |
| `b35e7c3` | Phase 2 Plan 02-07: add observer pattern manual-gate-hit |

## Final Audit Output

```
$ grep -rEn 'read -[pr]|read.*PROMPT' \
    scripts/ark-deliver.sh scripts/ark-team.sh scripts/execute-phase.sh \
    scripts/ark-budget.sh scripts/self-heal.sh
scripts/ark-deliver.sh:263:    while IFS= read -r pf; do  # AOS: intentional gate (loop iterator over heredoc, not user-input prompt)
scripts/ark-team.sh:196:      while IFS= read -r _pf; do  # AOS: intentional gate — stream parsing, not stdin
scripts/execute-phase.sh:143:  while IFS= read -r pf; do  # AOS: intentional gate — stream parsing, not stdin
scripts/execute-phase.sh:608:  echo "$tasks" | while IFS= read -r task; do  # AOS: intentional gate — stream parsing, not stdin

# After filtering intentional gates:
$ grep -rEn 'read -[pr]|read.*PROMPT' <5 scripts> | grep -v 'AOS: intentional gate'
(empty — CLEAN)
```

## Self-Check: PASSED

- scripts/ark-team.sh: FOUND (line 196 tagged)
- observability/observer/patterns.json: FOUND (15 patterns, manual-gate-hit present)
- Commit 1b0fdb6: FOUND
- Commit b35e7c3: FOUND
