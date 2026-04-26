---
phase: 04-bootstrap-autonomy
plan: 05
subsystem: bootstrap-customer-layer
tags: [bootstrap, customer, cascading-config, policy, mkdir-lock]
requirements: [REQ-AOS-18]
dependency-graph:
  requires: ["04-01"]
  provides: ["customer-layer cascading config", "mkdir-lock customer-dir init"]
  affects: ["scripts/bootstrap-policy.sh consumers", "scripts/ark-policy.sh"]
tech-stack:
  added: []
  patterns: ["mkdir-lock (Phase 3)", "double-checked locking", "cascading config layers"]
key-files:
  created: []
  modified:
    - scripts/lib/bootstrap-customer.sh
    - scripts/lib/policy-config.sh
decisions:
  - "Customer layer slots between project and vault (env > project > customer > vault > default)"
  - "Customer resolved from ARK_CUSTOMER env first, else project policy's bootstrap.customer key"
  - "First-time init seeds <customer>/policy.yml with customer.name + customer.created and commented examples"
  - "mkdir-lock parent dir created with mkdir -p before lock acquire (lockdir itself stays atomic)"
metrics:
  completed: 2026-04-26
  tasks: 2
---

# Phase 4 Plan 04-05: Bootstrap-Customer Hardening + Cascading Customer Layer Summary

Hardened the 04-01 stub `bootstrap-customer.sh` with mkdir-lock-safe idempotent customer-dir init that seeds `<customer>/policy.yml`, and inserted a fourth cascading layer into `policy-config.sh` so per-customer overrides are honored between project and vault.

## What changed

### `scripts/lib/bootstrap-customer.sh` (commit `91b4950`)
- Replaced stub `bootstrap_customer_init` with mkdir-lock + double-checked-locking implementation.
- Added `_bc_acquire_lock` / `_bc_release_lock` helpers (mirrors Phase 3 `policy-learner.sh` pattern).
- First-time creation seeds `policy.yml` with `customer.name`, `customer.created`, and commented override examples (`bootstrap.deploy_override`, `bootstrap.stack_override`).
- Self-test: 6/6 PASS — creates dir, idempotent (md5-equality), resolves seeded value, default fallback, concurrent-init (5 parallel forks → no lock leak), Bash 3 compat.

### `scripts/lib/policy-config.sh` (commit `0ab1d9e`)
- Inserted customer layer (2.5) into `policy_config_get` between project and vault.
- Mirrored the same logic in `policy_config_has` and extended `policy_config_dump` to label `customer` as a source.
- Customer resolution order: `$ARK_CUSTOMER` env > `<project>/.planning/policy.yml` `bootstrap.customer:` > skipped.
- Self-test: 13/13 PASS (10 existing, untouched + 3 new for customer layer).

## Cascading Truth Table

For a key resolved via `policy_config_get`, which layer wins:

| Key                              | env | project | customer | vault | default | Winner       |
| -------------------------------- | --- | ------- | -------- | ----- | ------- | ------------ |
| `budget.monthly_escalate_pct`    | —   | 80      | 85       | 90    | 95      | **project (80)**  |
| `custom.test_key` (env-customer) | —   | —       | customer_value | — | default_value | **customer**      |
| `bootstrap.deploy_override`      | —   | —       | —        | —     | fallback | **default**       |
| `self_heal.max_retries` (env)    | 7   | —       | —        | 3     | 99      | **env (7)**       |
| `custom.test_key` (proj-customer) | — | —       | customer_value | — | default_value | **customer (resolved via project's `bootstrap.customer`)** |

## Self-Test Output

**bootstrap-customer.sh:**
```
✅ init creates customer dir + policy.yml
✅ idempotent: file unchanged on re-init
✅ resolve_policy reads seeded value
✅ resolve_policy default fallback
✅ concurrent init: lock released, file exists
✅ no Bash 4 constructs
✅ ALL BOOTSTRAP-CUSTOMER TESTS PASSED (6/6)
```

**policy-config.sh:**
```
✅ default fallback when no config
✅ vault overrides default
✅ project overrides vault
✅ env (canonical) overrides project
✅ legacy env (ARK_MONTHLY_ESCALATE_PCT) overrides project
✅ vault used when project has no key
✅ has() returns 1 when no source has the key
✅ has() returns 0 when env set
✅ dump shows project source for overridden key
✅ no Bash 4-only constructs in main code
✅ customer overrides vault for unique key (env-resolved customer)
✅ project still overrides customer
✅ customer resolved from project policy bootstrap.customer
✅ ALL POLICY-CONFIG TESTS PASSED (13/13)
```

## Regressions
- `bash scripts/bootstrap-policy.sh test` → 16/16 PASS (unchanged)
- `bash scripts/ark-policy.sh test` → 15/15 PASS (unchanged)

## Cross-check
```bash
$ ARK_HOME=/tmp/empty-vault ARK_CUSTOMER=foo policy_config_get bootstrap.deploy_override fallback
fallback
```
Verifies the customer layer fails closed (default fallback) when the customer dir doesn't exist.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] mkdir-lock failed when `customers/` parent dir didn't exist**
- **Found during:** Task 1 self-test execution.
- **Issue:** First-time init creates `<vault>/customers/<slug>.lock` non-recursively (atomic mkdir is the lock primitive). On a fresh vault, `<vault>/customers/` doesn't exist yet, so every `mkdir "$lockdir"` call fails with ENOENT and the lock acquire times out — init silently exits 0 without creating anything (5/5 concurrent calls all "yielded" to a non-existent winner).
- **Fix:** Added `mkdir -p "$(dirname "$dir")"` immediately before `_bc_acquire_lock`. The lockdir itself remains atomic (single-component non-recursive mkdir); only its parent is pre-created.
- **Files modified:** `scripts/lib/bootstrap-customer.sh`
- **Commit:** `91b4950`

**2. [Plan delta] policy-config.sh test count: plan said 12, actual is 13**
- The plan's "Test 11" assertion contains two `assert_eq` calls (customer-overrides-vault + project-still-overrides-customer). Each `assert_eq` increments the counter, so what the plan named as 2 new tests landed as 3 assertions. Net: 10 pre-existing + 3 new = 13. All pass; final summary string is `(13/13)`.

## Self-Check: PASSED
- `scripts/lib/bootstrap-customer.sh` modified (commit `91b4950`)
- `scripts/lib/policy-config.sh` modified (commit `0ab1d9e`)
- Both self-tests pass; both regression suites pass.
