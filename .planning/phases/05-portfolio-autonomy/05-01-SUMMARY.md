---
phase: 05-portfolio-autonomy
plan: 01
subsystem: portfolio-priority-engine
tags: [aos, phase-5, wave-1, foundation, bash-3]
requirements:
  - REQ-AOS-23
dependency_graph:
  requires:
    - scripts/ark-policy.sh::_policy_log
    - scripts/lib/policy-config.sh (transitive via ark-policy.sh)
  provides:
    - scripts/ark-portfolio-decide.sh::portfolio_scan_candidates
    - scripts/ark-portfolio-decide.sh::portfolio_score_project
    - scripts/ark-portfolio-decide.sh::portfolio_pick_winner
    - scripts/ark-portfolio-decide.sh::portfolio_decide
    - "Sentinel sections (budget-reader, ceo-directive, audit-and-cooldown) for Wave-2 parallel fan-out"
  affects:
    - "scripts/ark-deliver.sh (Plan 05-05 will source this lib for no-args branch)"
tech-stack:
  added: []
  patterns:
    - "sourced bash 3 library (no top-level set -e)"
    - "sentinel-section parallelism contract (Wave-2 fills disjoint regions)"
    - "graceful-degradation source pattern (mirrors ark-policy.sh / bootstrap-policy.sh)"
key-files:
  created:
    - scripts/ark-portfolio-decide.sh
  modified: []
decisions:
  - "Stub _portfolio_budget_headroom returns 100 (Plan 05-02 overrides via type-check)"
  - "Stub _portfolio_ceo_priority returns 0 (Plan 05-03 overrides via type-check)"
  - "Tie-break uses STATE.md mtime (D-TIE-BREAK)"
  - "Empty portfolio returns empty + exit 0 (caller decides escalation)"
metrics:
  duration: "~6 minutes"
  completed: 2026-04-26
---

# Phase 5 Plan 05-01: ark-portfolio-decide.sh Foundation Summary

Sourceable bash 3 priority engine that walks `$ARK_PORTFOLIO_ROOT` (default `~/code`),
scores each `.planning/STATE.md`-bearing project against the locked formula
`stuckness*3 + falling_health*2 + (headroom>20?1:0) + ceo_priority*5`, and selects
the highest-priority winner with mtime tie-break. Self-test passes 20/20 in an
isolated `mktemp -d` vault; real `~/vaults/ark/observability/policy.db` md5
verified unchanged. Three empty sentinel sections in place for Wave-2 (05-02
budget reader, 05-03 CEO directive, 05-04 audit + cool-down) to fill in parallel
without merge conflicts.

## File

- **Path:** `scripts/ark-portfolio-decide.sh`
- **Line count:** 536
- **Executable:** yes (chmod +x)
- **Sourceable:** yes (no top-level `set -e`)

## Public API (4 functions, all `type -t function`)

| Function                       | Purpose                                                           |
|--------------------------------|-------------------------------------------------------------------|
| `portfolio_scan_candidates`    | Walk root depth-3, echo project paths (one per line, sorted/uniq) |
| `portfolio_score_project`      | Emit 8-field TSV: path/customer/phase/stuckness/fh/headroom/ceo/total |
| `portfolio_pick_winner`        | Sort by total desc, mtime tie-break; echo winner or empty        |
| `portfolio_decide`             | Pick + audit-log via `_policy_log "portfolio" SELECTED ...`      |

## Private helpers (`_portfolio_*`)

- `_portfolio_mtime` (BSD/GNU stat fallback)
- `_portfolio_read_yaml_key` (mirrors `policy-config.sh::_pc_read_yaml_key`)
- `_portfolio_read_customer` (reads `bootstrap.customer`, defaults `scratch`)
- `_portfolio_stuckness` (0|1|2 — blocked > 7d-stale > fresh)
- `_portfolio_falling_health` (0|1 — last-2 pass-count diff in delivery-logs)

## Sentinel sections (line numbers — Wave-2 plans need these)

| Section               | Open  | Close | Owner   |
|-----------------------|-------|-------|---------|
| budget-reader         | 304   | 309   | 05-02   |
| ceo-directive         | 311   | 315   | 05-03   |
| audit-and-cooldown    | 317   | 322   | 05-04   |

Format is exactly `# === SECTION: <name> ===` ... `# === END SECTION: <name> ===`;
Wave-2 plans insert function definitions between matching markers. Disjoint
regions = no merge conflict.

## Self-test results — 20/20 passed

| # | Assertion                                                            | Status |
|---|----------------------------------------------------------------------|--------|
| 1 | `portfolio_scan_candidates` finds 3 projects                         | ✅     |
| 2 | proj-a customer → `scratch` (no policy.yml)                          | ✅     |
| 3 | proj-b customer → `acme`                                             | ✅     |
| 4 | proj-c customer → `beta`                                             | ✅     |
| 5 | proj-a stuckness → 0 (fresh, active)                                 | ✅     |
| 6 | proj-b stuckness → 1 (>7d stale, via `touch -t -10d`)                | ✅     |
| 7 | proj-c stuckness → 2 (`status: blocked`)                             | ✅     |
| 8 | `portfolio_score_project` emits 8 TSV fields                         | ✅     |
| 9 | proj-c total ≥ 6 (got 7: stuckness 2*3 + headroom_bonus 1)           | ✅     |
| 10| `portfolio_pick_winner` → proj-c (highest score)                     | ✅     |
| 11| Tie-break → most-recently-touched (proj-a after equalising)          | ✅     |
| 12| Empty portfolio → empty stdout + exit 0                              | ✅     |
| 13| `portfolio_decide` invokes `_policy_log class=portfolio SELECTED`    | ✅     |
| 14| No `declare -A` in main code (Bash 3 compat)                         | ✅     |
| 15| No `read -p` in delivery-path (excludes comments)                    | ✅     |
| 16| `SECTION: budget-reader` open + close present                        | ✅     |
| 17| `SECTION: ceo-directive` open + close present                        | ✅     |
| 18| `SECTION: audit-and-cooldown` open + close present                   | ✅     |
| 19| Real `~/vaults/ark/observability/policy.db` md5 unchanged            | ✅     |
| 20| `portfolio_pick_winner` empty exit code = 0                          | ✅     |

(Plan required ≥12; delivered 20.)

## Bash-3 compat — confirmed

- `grep -nE '^[[:space:]]*declare[[:space:]]+-A' scripts/ark-portfolio-decide.sh` → no matches in code (only in header comment + self-test regex literal)
- No `${var,,}`, no `mapfile`/`readarray`
- `tr` for case-fold-equivalents; `awk` for YAML; `$(( ... ))` for arithmetic
- BSD `stat -f %m` first, GNU `stat -c %Y` fallback (macOS-compatible mtime)
- `date -v -10d` first, `date -d '10 days ago'` fallback in self-test backdate

## Acceptance criteria — all green

- ✅ File exists, is executable, sourceable (no top-level `set -e`)
- ✅ `bash scripts/ark-portfolio-decide.sh test` exits 0
- ✅ Self-test reports 20 assertions all passing (≥ 12 required)
- ✅ All three sentinel sections present and EMPTY (Wave 2 fills them)
- ✅ `grep -c 'declare -A'` in code = 0 (1 match is in header comment only)
- ✅ No `read -p` in production code paths
- ✅ Sourcing the script defines all 4 public functions

## Deviations from Plan

None — plan executed exactly as written. One minor in-flight refinement of the
`read -p` regression assertion to exclude comment lines (the rule itself was
documented in the header comment, which trivially matched the pattern); this
is a self-test-only adjustment, not a deviation from delivered behaviour.

## Self-Check: PASSED

- ✅ scripts/ark-portfolio-decide.sh exists (536 lines)
- ✅ All 4 public functions declared and `type -t function`
- ✅ Self-test 20/20 (commit hash recorded below)
- ✅ Real `~/vaults/ark/observability/policy.db` md5 unchanged
- ✅ All three sentinel sections present at documented line numbers
