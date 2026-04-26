---
phase: 02-autonomy-policy
plan: 03
subsystem: budget-policy-wiring
tags: [aos, budget, policy, escalation]
requires: [02-01]
provides: [budget-black-tier-policy-routed, budget-auto-reset, budget-monthly-escalation]
affects: [scripts/ark-budget.sh]
key_files:
  modified:
    - scripts/ark-budget.sh
decisions:
  - "BLACK tier no longer hard-stops; policy_budget_decision decides AUTO_RESET vs ESCALATE_MONTHLY_CAP vs PROCEED"
  - "AUTO_RESET path zeros phase_used in budget.json, logs auto_reset_by_policy event, and recomputes tier so notification reflects post-reset state (typically GREEN)"
  - "ESCALATE_MONTHLY_CAP path leaves BLACK tier in place (visual notification still fires) and delegates to ark_escalate(monthly-budget) without halting the calling script"
  - "Idempotency: an open monthly-budget escalation matching the current monthly_period suppresses duplicate ark_escalate calls"
  - "Sourcing of ark-policy.sh and ark-escalations.sh is conditional with graceful degradation if the libs are missing"
  - "All embedded Python uses the env-passing heredoc idiom (BUDGET_FILE env var + os.environ + <<'PY') per NEW-B-3 lesson — no $VAR interpolation inside Python heredocs"
metrics:
  tasks_completed: 2
  commits: 2
  duration_minutes: ~10
  completed: 2026-04-26
---

# Phase 2 Plan 02-03: ark-budget.sh Wired to Policy — Summary

Replaces the legacy BLACK-tier hard-stop in `scripts/ark-budget.sh` with a policy-routed
decision. The script now sources `ark-policy.sh` (and `ark-escalations.sh` when available),
and on BLACK detection asks `policy_budget_decision` whether to auto-reset the phase
counter or escalate via the queue. Behavior on GREEN/YELLOW/ORANGE/RED is unchanged.

## Tasks completed

| # | Name | Commit |
|---|------|--------|
| 1 | Source ark-policy.sh + ark-escalations.sh at top of ark-budget.sh | `be00617` |
| 2 | Route BLACK-tier through policy_budget_decision; auto-reset or escalate | `09d517b` |

## Helper function added

`_budget_apply_policy_on_black()` (in `scripts/ark-budget.sh`):

- Returns 0 if the policy returned `AUTO_RESET` (caller recomputes tier).
- Returns 1 if escalated, no policy lib sourced, or `PROCEED`.
- Reads phase_used / phase_cap / monthly_used / monthly_cap / monthly_period from
  `budget.json` via env-passing heredoc (`BUDGET_FILE="$BUDGET_FILE" python3 - <<'PY'`).
- On `AUTO_RESET`: zeros `phase_used`, appends an `auto_reset_by_policy` row to
  `budget-events.jsonl`.
- On `ESCALATE_MONTHLY_CAP`: idempotency-checks `~/vaults/ark/ESCALATIONS.md` for an
  open `monthly-budget` section matching the current `monthly_period`. If absent and
  `ark_escalate` is sourced, calls `ark_escalate monthly-budget "Monthly cap reached" "<body>"`.

## Call sites that delegate to the helper

1. `notify_tier_change` — when `new_tier == "BLACK"`, calls helper before writing the
   tier file. If the helper returns 0, recomputes `new_tier=$(compute_tier)` so the
   downstream visual notification + budget-events line reflect the post-reset tier.
2. `check)` case branch — replaces the bare `exit 1`. On `AUTO_RESET` exits 0 with
   `"✅ Tier (post auto-reset by policy): <tier>"`; otherwise prints the legacy
   `🛑 BUDGET EXHAUSTED` message and exits 1.

## Synthetic test outputs

### Auto-reset path (phase_used=50000, monthly_used=60000)

```
✅ Tier (post auto-reset by policy): GREEN
exit=0
phase_used after: 0
AUTO_RESET TEST: OK
```

policy-decisions.jsonl entry:
```json
{"ts":"2026-04-26T12:06:11Z","schema_version":1,"decision_id":"20260426T120611Z-a98ac0e283a09575","class":"budget","decision":"AUTO_RESET","reason":"phase_cap_hit_monthly_headroom_6pct","context":{"phase_used":50000,"phase_cap":50000,"monthly_used":60000,"monthly_cap":1000000},"outcome":null,"correlation_id":null}
```

budget-events.jsonl entry:
```json
{"timestamp":"2026-04-26T12:06:11Z","project":"btest","event":"auto_reset_by_policy","reason":"BLACK_with_monthly_headroom"}
```

### Escalate path (phase_used=50000, monthly_used=960000 — 96% of cap)

```
🛑 BUDGET EXHAUSTED — exit 1
exit=1
phase_used after: 50000 (NOT reset — correct)
```

ESCALATIONS.md entry written:
```
## ESC-20260426-120625-test01 — monthly-budget — open

Monthly cap reached

Monthly cap reached.

monthly_period: 2026-04
phase_used: 50000 / 50000
monthly_used: 960000 / 1000000

Review: ark budget --set-monthly <bigger> OR start new monthly period.
```

policy-decisions.jsonl entry:
```json
{"ts":"2026-04-26T12:06:25Z","schema_version":1,"decision_id":"20260426T120625Z-27adfe0583b1abbf","class":"budget","decision":"ESCALATE_MONTHLY_CAP","reason":"monthly_use_96pct_>=_95pct","context":{"phase_used":50000,"phase_cap":50000,"monthly_used":960000,"monthly_cap":1000000},"outcome":null,"correlation_id":null}
```

Idempotency: a second `--check` invocation produced **1** ESCALATIONS.md section (no duplicate).

### CLI surface preserved

Empty-budget smoke (no policy interaction):

```
$ bash scripts/ark-budget.sh --tier         → GREEN
$ bash scripts/ark-budget.sh --route engineering → codex
$ bash scripts/ark-budget.sh --check        → ✅ Tier: GREEN
$ bash scripts/ark-budget.sh                → 🟢 Ark Budget — Tier: GREEN ...
```

## Verification checks (per plan)

| Check | Result |
|-------|--------|
| `bash -n scripts/ark-budget.sh` | passes |
| `grep -E 'read -[pr]' scripts/ark-budget.sh` | 0 hits |
| `grep -c 'policy_budget_decision' scripts/ark-budget.sh` | 2 |
| `grep -c 'ark_escalate' scripts/ark-budget.sh` | 2 |
| Forced-BLACK with monthly headroom auto-resets phase_used to 0 | yes |
| Forced-BLACK with monthly_used≥95% writes ESCALATIONS.md monthly-budget section | yes |
| Repeat invocation does not duplicate the escalation section | yes (1 entry after 2 runs) |
| GREEN/YELLOW/ORANGE/RED CLI behavior identical | yes |

## Deviations from plan

None — plan executed as written. The env-passing heredoc idiom (NEW-B-3) was
applied verbatim in the new helper. No new `read -p`/`read -r` calls were introduced.

## Notes

- 02-02 (ark-escalations.sh) has not yet been executed. The graceful-degradation
  path in this plan covers that case: `_budget_apply_policy_on_black` checks
  `type ark_escalate >/dev/null 2>&1` before calling. Smoke tests stubbed
  `ark_escalate` to validate the wiring contract end-to-end.
- The escalation body uses fixed key/value lines (`monthly_period: …`) so the
  idempotency `grep -F` check in the helper matches what 02-02's writer is
  expected to preserve verbatim inside the section body.

## Self-Check: PASSED

- File modified: `/Users/jongoldberg/vaults/automation-brain/scripts/ark-budget.sh` — FOUND
- Commit `be00617` (Task 1) — FOUND
- Commit `09d517b` (Task 2) — FOUND
