---
phase: 02-autonomy-policy
plan: 06b
status: complete
commit: 886a3bc
requirements: [REQ-AOS-01, REQ-AOS-02]
files_modified:
  - scripts/self-heal.sh
files_created:
  - .planning/phases/02-autonomy-policy/02-06b-PRESTATE.md
  - .planning/phases/02-autonomy-policy/02-06b-SUMMARY.md
key_links:
  - from: scripts/self-heal.sh
    to: scripts/ark-policy.sh
    via: source + _policy_log (every class:self_heal line) + policy_dispatcher_route (layer 2)
  - from: scripts/self-heal.sh
    to: scripts/ark-escalations.sh
    via: ark_escalate repeated-failure (layer 3, type-guarded — 02-02 not yet shipped)
---

# Phase 2 Plan 02-06b: self-heal.sh layered retry refactor — Summary

## Objective met

`scripts/self-heal.sh` now implements CONTEXT.md decision #4 — the three-layer self-heal retry contract — while preserving its legacy 2-arg proposal-file behaviour for existing callers (`execute-phase.sh`, `ark-deliver.sh`, `ark-error-monitor.sh`).

## Pre-state

- `scripts/self-heal.sh`: 162 lines, SHA1 `660598d2559a8f671cc9176d765895b8ba2bef2d`
- All current callers pass 2 args (`<error_log_path> <context>`); zero callers used a 4-arg shape, so `--retry` mode is purely additive.
- See `02-06b-PRESTATE.md` for full caller inventory.

## Post-state diff summary

- +338 insertions / -1 deletion to `scripts/self-heal.sh`.
- Added at top: source of `ark-policy.sh` (graceful) + source of `ark-escalations.sh` (type-guarded — 02-02 not yet shipped, layer 3 still emits a sentinel and audit line).
- Added 3 layer helpers + 1 dispatcher (line numbers below).
- Added mode dispatcher branch (`--retry` sentinel → calls `self_heal_retry_layer "$@"; exit $?`) BEFORE the legacy `ERROR_LOG="${1:?...}"` line.
- Legacy path (lines 274+ post-edit) unchanged byte-for-byte.

## Layer entry points (line numbers)

| Layer | Function                              | Line |
| ----- | ------------------------------------- | ---- |
| 1     | `_self_heal_layer_enriched`           | 43   |
| 2     | `_self_heal_layer_escalate_model`     | 109  |
| 3     | `_self_heal_layer_escalate_queue`     | 171  |
| —     | `self_heal_retry_layer` (dispatcher)  | 197  |
| —     | `--retry` mode branch                 | 224  |

## NEW-B-2 enforcement (single audit writer)

```
$ grep -c '_self_heal_log' scripts/self-heal.sh         → 0
$ grep -c '"schema_version":1' scripts/self-heal.sh      → 0
$ grep -c '_policy_log self_heal' scripts/self-heal.sh   → 5  (≥3, one per layer + ok/empty branches)
$ grep -cE 'read -[pr]' scripts/self-heal.sh             → 0
```

Every `class:self_heal` line is emitted by `_policy_log` from sourced `ark-policy.sh`. Inline writers and inline schema literals are absent.

## Synthetic 3-call test trace

Isolated `ARK_HOME=/tmp/sh-test-vault` with copied `ark-policy.sh` + `lib/`. Three successive calls to `self-heal.sh --retry test-task-1 <prompt> <output>` against a synthetic prompt with no live dispatchers:

```
Call 1 (count 0 → layer 1): exit=1, count_file=1     [empty_output — no codex/gemini/api-key in test env]
Call 2 (count 1 → layer 2): exit=1, count_file=2     [empty_output — chosen=gemini, but no dispatcher]
Call 3 (count 2 → layer 3): exit=2, count_file=3     [queued — output_file populated]

output_file:
  verdict: ESCALATED
  summary: self-heal exhausted (test-task-1, 3 retries)
```

Counter progression `0→1→2→3` confirmed. Exit codes match spec (1/1/2).

## ESCALATIONS.md entry produced on layer 3

`ark-escalations.sh` has not been shipped yet (02-02 still pending in Wave 2). The layer-3 helper type-guards `ark_escalate` and gracefully emits the sentinel + audit line without it. Once 02-02 lands and exports `ark_escalate`, the layer-3 path will append to `~/vaults/ark/ESCALATIONS.md` automatically — no further change to `self-heal.sh` required.

Functional check today: layer 3 still **succeeds** in writing `verdict: ESCALATED` to `output_file` and emits the `RETRY_3_ESCALATE_QUEUE` audit line, exiting 2 — caller behaviour is correct regardless of 02-02 readiness.

## Audit-log schema sample (proves _policy_log was used)

Sample line from layer 3 of the synthetic test (pretty-printed):

```json
{
  "ts": "2026-04-26T12:07:17Z",
  "schema_version": 1,
  "decision_id": "20260426T120717Z-947f419eb27542cd",
  "class": "self_heal",
  "decision": "RETRY_3_ESCALATE_QUEUE",
  "reason": "queued",
  "context": {"task_id": "test-task-1", "layer": 3},
  "outcome": null,
  "correlation_id": null
}
```

All required fields present per 02-01 locked schema (`decision_id` matches `<YYYYMMDDTHHMMSSZ>-<16-hex>`, `outcome:null`, `correlation_id` field present, `schema_version:1`). Phase 3's observer-learner can patch by `decision_id`.

## Legacy-mode regression test

```
$ bash scripts/self-heal.sh /tmp/fake-error.log "test-context"
  → produces $ARK_HOME/self-healing/proposed/heal-<ts>.md
  → exit 1 (no AI dispatcher in isolated test env — same legacy fallback as before)
```

Behaviour identical to pre-refactor: existing callers (`execute-phase.sh:507`, `ark-deliver.sh:438`) see no change.

## Caller list (today)

| Caller                            | Args passed | Mode used   | Action needed |
| --------------------------------- | ----------- | ----------- | ------------- |
| `scripts/execute-phase.sh:507`    | 2           | Legacy A    | None (02-06 Task 2 will optionally migrate to `--retry`) |
| `scripts/ark-deliver.sh:438`      | 2           | Legacy A    | None |
| `hooks/ark-error-monitor.sh:8`    | (var only)  | n/a         | None |
| `scripts/ark-doctor.sh:66`        | (existence probe) | n/a   | None |

## Verification matrix

| Check                                                            | Result |
| ---------------------------------------------------------------- | ------ |
| `bash -n scripts/self-heal.sh`                                   | PASS   |
| `grep -c '_self_heal_log\|"schema_version":1' scripts/self-heal.sh` returns 0 | PASS (0) |
| `grep -c '_policy_log self_heal' scripts/self-heal.sh` ≥ 3       | PASS (5) |
| `grep -cE 'read -[pr]' scripts/self-heal.sh` returns 0           | PASS (0) |
| 3 layer helpers defined                                          | PASS   |
| Synthetic 3-call test: counter 0→1→2→3, exits 1/1/2              | PASS   |
| Layer 3 writes `verdict: ESCALATED` to output_file               | PASS   |
| All 3 audit lines contain decision_id + outcome:null + correlation_id + schema_version:1 | PASS |
| Legacy 2-arg path produces proposal file (regression)            | PASS   |

## Self-Check: PASSED

- `scripts/self-heal.sh`: FOUND
- `.planning/phases/02-autonomy-policy/02-06b-PRESTATE.md`: FOUND
- Commit `886a3bc`: FOUND in `git log --oneline`
