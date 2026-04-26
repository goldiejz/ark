---
phase: 06-cross-customer-learning
plan: 03
subsystem: cross-customer-learning
tags: [lesson-promoter, apply-pending, atomic-write, idempotency, audit, mkdir-lock]
requires:
  - 06-02 (apply-pending sentinel + classification verdicts TSV contract)
  - Phase 2 _policy_log single-writer (ark-policy.sh)
provides:
  - promoter_apply_pending function (durable PROMOTE/DEPRECATED/MEDIOCRE side-effects)
  - Managed-section format on universal-patterns.md and anti-patterns.md
  - Idempotency marker contract (locked for downstream consumers)
  - lesson_promote audit class (PROMOTED / DEPRECATED / MEDIOCRE_KEPT_PER_CUSTOMER)
affects:
  - $ARK_HOME/lessons/universal-patterns.md (managed section)
  - $ARK_HOME/bootstrap/anti-patterns.md (managed section)
  - $ARK_HOME/observability/policy.db (lesson_promote audit rows)
tech-stack:
  added: []
  patterns:
    - mkdir-lock (Phase 3 policy-learner pattern, ported domain-faithfully)
    - tmp+mv atomic write (cat target + new block → tmp → mv)
    - Per-cluster canonical marker for idempotency (literal-string grep -F)
    - Single-writer audit via _policy_log
key-files:
  created:
    - .planning/phases/06-cross-customer-learning/06-03-SUMMARY.md
  modified:
    - scripts/lesson-promoter.sh (apply-pending sentinel filled + 1 minimal `--apply` orchestrator change passing LP_CLUSTER_TSV)
decisions:
  - 06-03-D1: Idempotency marker = `<!-- AOS Phase 6 — auto-promoted: <slug>-cluster-<N> -->`. Slug = lower-cased, alphanumerics-only, hyphen-separated, 60-char truncated title-seed; cluster-id appended for diagnostics but slug match alone suffices for de-dup (ensures stability under re-clustering when cluster_id reshuffles).
  - 06-03-D2: Customer/citation/seed-body data flow via env LP_CLUSTER_TSV pointing at the cluster TSV emitted by promoter_cluster_similar. Helpers (_lp_customers_for, _lp_seed_body_for, _lp_citations_for) degrade to placeholders if the env is absent.
  - 06-03-D3: MEDIOCRE_KEPT_PER_CUSTOMER audit rows are gated behind `LESSON_AUDIT_MEDIOCRE=1` (default off) to keep audit-DB signal-to-noise high; Phase 7 can flip the env for diagnostics.
  - 06-03-D4: Lock at $VAULT_PATH/.lesson-promoter.lock acquired ONCE per promoter_apply_pending invocation (not per-row) — different scope from policy-learner's per-line lock — because all writes target two known files in one vault and the bottleneck is the vault not the row.
metrics:
  duration: ~25min
  completed: 2026-04-26
---

# Phase 6 Plan 06-03: promoter_apply_pending — Atomic Vault Writes + Audit + Idempotency Summary

Filled the apply-pending sentinel laid down by 06-02 with a complete
durable-side-effects implementation: cluster verdicts → atomic markdown
appends to `universal-patterns.md` / `anti-patterns.md` under mkdir-lock,
single-writer `_policy_log` audit rows (`class=lesson_promote`), and per-cluster
git commits in the vault repo. Idempotent across re-runs; concurrency-safe via
mkdir-lock.

## Final managed-block format (locked for downstream consumers)

```markdown
<!-- AOS Phase 6 — auto-promoted: <slug>-cluster-<N> -->
## <title seed text>

**Customers:** <customer-a>, <customer-b>[, ...]
**Combined occurrences:** <lesson_count>
**Cluster ID:** <N>
**Promoted:** <ISO-8601 UTC>

<rule body of the cluster seed lesson, verbatim with leading "## Lesson:" stripped>

**Source lessons:**
- <customer-a>: <relpath under $ARK_PORTFOLIO_ROOT>
- <customer-b>: <relpath>
[...]

---
```

A leading blank line is emitted before the marker on every append so successive
managed blocks don't run together. The trailing `---` separates blocks visually
in rendered markdown.

## Idempotency marker (locked)

```
<!-- AOS Phase 6 — auto-promoted: <slug>-cluster-<N> -->
```

- `slug` = `_lp_slug "<title>"` → lower-cased, every non-alphanumeric replaced
  with `-`, runs collapsed, leading/trailing trimmed, truncated to 60 chars.
- `<N>` = numeric cluster_id from promoter_cluster_similar.
- Lookup uses `grep -F -q` (literal string) — no regex traps.
- Same cluster, same slug, same `<N>` → skipped on re-run, increments
  `skipped_idempotent` counter.
- Re-clustering that produces the same logical group at a different `<N>` will
  technically re-append (different marker). Slug match alone is the primary
  de-dup; cluster_id is diagnostic. In the current dataset cluster_ids are
  insertion-stable, so this is a non-issue; flagged for Phase 7 if it becomes one.

## Audit row schema

```
class:           lesson_promote
decision:        PROMOTED  |  DEPRECATED  |  MEDIOCRE_KEPT_PER_CUSTOMER
reason (PROMOTED):    customers_${C}_lessons_${L}_route_${ROUTE}
reason (DEPRECATED):  conflict_customers_${C}_lessons_${L}
reason (MEDIOCRE):    below_threshold_customers_${C}
context (JSON):  {"cluster_id":N,"title_seed":"...","lesson_count":L,"route":"<route>"}
correlation_id:  null  (cross-cluster decisions don't chain a single source decision_id)
```

Single-writer rule (Phase 2) honoured: every audit write goes through
`_policy_log`. No inline `INSERT INTO decisions` anywhere in
`scripts/lesson-promoter.sh` — verified with `grep -nE 'INSERT INTO decisions'`
returning zero non-comment hits.

## Concurrency test outcome

Two parallel `promoter_apply_pending` invocations against the same isolated
tmp vault, both writing the same synthetic PROMOTE cluster:

- mkdir-lock at `$VAULT_PATH/.lesson-promoter.lock` serialises them — only one
  passes `mkdir` at a time.
- The first invocation appends + commits; the second observes the canonical
  marker via `grep -F -q` and treats the cluster as `skipped_idempotent` →
  no second append, no second commit.
- Net delta: exactly **1** new git commit across the two parallel runs (asserted).
- Lock dir absent at end of both runs (asserted).

## Sentinel + scope discipline

**Confirmed**: only the apply-pending sentinel region (`scripts/lesson-promoter.sh`
lines 293–582, 288 lines inside the markers) was filled in, plus the one
minimal `promoter_run --apply` change that constructs an `LP_CLUSTER_TSV`
sidecar so `promoter_apply_pending` can resolve customer/citation/seed-body
without re-scanning. No other code outside the sentinel was modified.

`grep -n '^# === SECTION: apply-pending (Plan 06-03) ===' scripts/lesson-promoter.sh`
→ exactly one anchored open marker (line 293).
`grep -n '^# === END SECTION: apply-pending ===' scripts/lesson-promoter.sh`
→ exactly one anchored close marker (line 582).

## Real-vault md5 invariance (held)

Captured before/after running the self-test twice (proves both initial run
and idempotent re-run are no-ops on real filesystem):

| File | Before | After |
| ---- | ------ | ----- |
| `~/vaults/ark/lessons/universal-patterns.md` | `7afcb1fcedecd4bcb11da2b7b53785d3` | `7afcb1fcedecd4bcb11da2b7b53785d3` ✅ |
| `~/vaults/ark/bootstrap/anti-patterns.md`     | (absent — no mutation possible) | (still absent) ✅ |
| `~/vaults/ark/observability/policy.db`        | `68873c513a115c8a79b6ecb2c4e8aaa4` | `68873c513a115c8a79b6ecb2c4e8aaa4` ✅ |

All three invariants held. The self-test exclusively redirects `VAULT_PATH`,
`ARK_HOME`, `UNIVERSAL_TARGET`, `ANTIPATTERN_TARGET`, `ARK_PORTFOLIO_ROOT`, and
`ARK_POLICY_DB` to a fresh `mktemp -d` vault and a `/tmp/ark-promoter-apply-$$.db`
SQLite file before any apply work. The previously existing assertion 14
(`VAULT_PATH redirected to tmp dir`) still passes — the apply-test block
extends, not regresses, the isolation contract.

## Self-test totals

- 18 assertions inherited from 06-02
- 19 new assertions added by 06-03 (apply-pending block)
- **37 total — all pass.**

New 06-03 assertions cover:

1. universal-patterns.md created with content after `--apply`
2. anti-patterns.md created with content after `--apply`
3. universal-patterns.md has ≥1 cluster canonical marker
4. anti-patterns.md has ≥1 cluster canonical marker
5. Audit DB has ≥2 `lesson_promote PROMOTED` rows
6. Tmp vault has ≥2 `AOS Phase 6: promote cluster` git commits
7. Lock dir absent after `--apply`
8. No `*.tmp.*` leftovers in vault target dirs (atomic-write hygiene)
9. Idempotency: universal-patterns.md line count unchanged on re-run
10. Idempotency: anti-patterns.md line count unchanged on re-run
11. Idempotency: git commit count unchanged on re-run
12. Idempotency: audit DB PROMOTED row count unchanged on re-run
13. DEPRECATED verdict: universal-patterns.md line count unchanged
14. DEPRECATED verdict: exactly 1 new `lesson_promote DEPRECATED` audit row
15. Concurrent: exactly 1 new commit from two parallel `--apply` invocations
16. Concurrent: lock dir released after parallel runs
17. Real-vault `universal-patterns.md` md5 unchanged
18. Real-vault `anti-patterns.md` md5 unchanged (absent → absent)
19. Real-vault `policy.db` md5 unchanged

## Deviations from Plan

None. Plan executed exactly as written. The only minor adaptation: the plan
suggested helpers degrade to placeholder strings if `LP_CLUSTER_TSV` is absent
— implemented exactly that way (e.g. `(unknown)` for customers, `_(seed body
not available)_` for body, `(citations not available)` for citations).

## Self-Check: PASSED

- File `scripts/lesson-promoter.sh` — present and edited inside sentinel only
- Section sentinel pair anchored to lines 293 / 582 (unique under `^`-anchored grep)
- 37/37 self-test assertions pass
- Real-vault md5 invariance held for all three sensitive files
- No inline `INSERT INTO decisions` (single-writer discipline)
- `bash -n scripts/lesson-promoter.sh` → clean
