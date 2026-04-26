# Phase 3 Plan Updates — SQLite Backend Substitution

**Date:** 2026-04-26 (post Phase 2.5 commit)
**Status:** Active — executors MUST honor these updates over the original plan text

The original 8 plans were drafted before Phase 2.5 (SQLite migration). Now the audit log is in SQLite, not JSONL. The high-level architecture is unchanged; the implementation simplifies dramatically.

## Substrate change

- Source: `~/vaults/ark/observability/policy.db` (SQLite, WAL mode, schema_version=1)
- Lib: `scripts/lib/policy-db.sh` exposes `db_init`, `db_insert_decision`, `db_count_decisions`, `db_tail_decisions`, `db_path`
- 61 rows already migrated; new writes go to SQLite via `_policy_log`

## Per-plan adjustments

### 03-01 — Outcome-tagger
- **Original:** Heuristic outcome inference + `jq` in-place patcher rewriting JSONL
- **Updated:** Heuristic outcome inference unchanged. Patcher uses `sqlite3 db "UPDATE decisions SET outcome = ? WHERE decision_id = ?"` — single `UPDATE` per decision, transactional.
- File: `scripts/lib/outcome-tagger.sh` exposes:
  - `tagger_infer_outcome <decision_id>` — returns `success | failure | ambiguous` based on logs+git within window (env `ARK_TAGGER_WINDOW_MIN`, default 10)
  - `tagger_patch_outcome <decision_id> <outcome>` — wraps `UPDATE decisions SET outcome=? WHERE decision_id=?`. Idempotent (no-op if outcome already matches).
  - `tagger_run_window <since_iso8601>` — iterates all `outcome IS NULL` rows where `ts >= since`, infers + patches each.

### 03-02 — Pattern scoring engine (`scripts/policy-learner.sh`)
- **Original:** Aggregation via 50-line jq pipeline reading the entire JSONL
- **Updated:** Single SQL query — see template below. ~10 lines of bash + 1 SQL block.
- Pattern tuple: `(class, decision, json_extract(context, '$.dispatcher'), json_extract(context, '$.complexity'))`. Where context lacks dispatcher/complexity, those fields are NULL — treated as a separate pattern bucket.
- Threshold logic unchanged: ≥5 occurrences + ≥80% success → PROMOTE; ≥5 + ≤20% → DEPRECATE; else IGNORE.
- True-blocker filter unchanged: never promote/deprecate `monthly-budget`, `architectural-ambiguity`, `destructive-op`, `repeated-failure`.
- Reference SQL:
  ```sql
  SELECT
    class, decision,
    json_extract(context, '$.dispatcher')   AS dispatcher,
    json_extract(context, '$.complexity')   AS complexity,
    COUNT(*)                                 AS n,
    SUM(outcome = 'success') * 1.0 / COUNT(*) AS success_rate
  FROM decisions
  WHERE outcome IS NOT NULL
    AND class NOT IN ('escalation','self_improve')
    AND ts >= datetime('now', '-7 days')
  GROUP BY class, decision, dispatcher, complexity
  HAVING n >= 5;
  ```

### 03-03 — Auto-patch policy.yml
- Largely unchanged. Still needs: mkdir-lock, atomic write, vault git commit, `_policy_log "self_improve" "PROMOTED"` audit entry.
- Source of patches: rows from 03-02 query above where `success_rate >= 0.80` (PROMOTE) or `success_rate <= 0.20` (DEPRECATE).
- Confidence: include `n` and `success_rate` in the audit entry's `context` JSON so Phase 3's own decisions can be patched in turn (recursive learning).

### 03-04 — Weekly digest writer
- Unchanged in intent. Implementation reads from SQLite via the same query as 03-02 (full window not just recent).
- Output: `~/vaults/ark/observability/policy-evolution.md` with three sections: PROMOTED, DEPRECATED, MEDIOCRE_MIDDLE (counts, rates, sample decision_ids).

### 03-05 — ark-deliver post-phase trigger
- **Important:** ark-deliver.sh is currently `.HALTED` (renamed externally after the strategix failed test). This plan must:
  1. Either restore ark-deliver.sh from `ark-deliver.sh.HALTED` and add the post-phase hook, OR
  2. Add the hook to whatever replaces it
- The hook itself: after `update_state "$phase_num" "complete"`, invoke `bash "$VAULT_PATH/scripts/policy-learner.sh" --since-phase "$phase_num"` non-fatally.

### 03-06 — `ark learn` subcommand
- Unchanged. Wires `ark learn [--full | --since DATE]` in `scripts/ark` dispatcher.

### 03-07 — Tier 9 verify suite
- **Updated:** All assertions go through SQLite, not JSONL.
- Synthetic data setup: `INSERT INTO decisions VALUES ...` for known patterns (rather than appending JSONL).
- Assert: PROMOTE fires for ≥5/≥80% pattern, DEPRECATE for ≥5/≤20%, MEDIOCRE_MIDDLE left alone.
- Assert: 4 true-blocker classes never appear in PROMOTE/DEPRECATE output.

### 03-08 — Docs (STRUCTURE.md + REQ-AOS-08..14 + STATE.md)
- Update STRUCTURE.md to reference SQLite as the substrate (Phase 2.5 already added an addendum; extend it for Phase 3).
- REQ-AOS-08..14 unchanged (the *requirements* are about behavior, not backend).

## Notes for executors

- All audit-log writes from Phase 3 modules MUST use `_policy_log` (single writer rule from Phase 2). Never inline `INSERT INTO decisions` from learner code — go through `_policy_log` so schema/decision_id/outcome semantics stay consistent.
- The migration tool `ark-migrate-jsonl-to-sqlite.sh` already imported the existing 61 rows; Phase 3 starts with real data to learn from.
- WAL mode handles concurrent reads; learner runs are read-mostly with one short UPDATE burst per outcome — should not conflict with a live `_policy_log` writer.
