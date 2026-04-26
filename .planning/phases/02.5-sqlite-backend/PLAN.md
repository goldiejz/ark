# Phase 2.5 — Audit Log: JSONL → SQLite Backend

**Status:** in-progress
**Driver:** AOS Phase 3 needs SQL-grade aggregations + in-place outcome patching; JSONL doesn't scale past ~10k rows for the learner's read patterns.

## Goal

Migrate `policy-decisions.jsonl` to `policy.db` (SQLite) preserving the locked `schema_version=1` contract. Phase 3 builds on the new backend.

## Schema (DDL)

```sql
CREATE TABLE IF NOT EXISTS decisions (
  decision_id     TEXT PRIMARY KEY,
  ts              TEXT NOT NULL,            -- ISO8601 UTC
  schema_version  INTEGER NOT NULL DEFAULT 1,
  class           TEXT NOT NULL,
  decision        TEXT NOT NULL,
  reason          TEXT NOT NULL,
  context         TEXT,                     -- JSON-serialized object or NULL
  outcome         TEXT,                     -- NULL | 'success' | 'failure' | 'ambiguous'
  correlation_id  TEXT REFERENCES decisions(decision_id)
);

CREATE INDEX IF NOT EXISTS idx_decisions_ts        ON decisions(ts);
CREATE INDEX IF NOT EXISTS idx_decisions_class     ON decisions(class);
CREATE INDEX IF NOT EXISTS idx_decisions_outcome   ON decisions(outcome);
CREATE INDEX IF NOT EXISTS idx_decisions_pattern   ON decisions(class, decision);

PRAGMA journal_mode=WAL;          -- multi-reader + single-writer concurrency
PRAGMA synchronous=NORMAL;        -- durable enough; faster than FULL
PRAGMA foreign_keys=ON;
```

## Tasks

1. `scripts/lib/policy-db.sh` — DDL initializer + `_db_init` helper, sourced by ark-policy.sh
2. `scripts/ark-policy.sh::_policy_log` — rewrite from `printf >> file` to sqlite3 INSERT
3. `scripts/ark-policy.sh::policy_audit` — rewrite from `tail -n` to `sqlite3 SELECT`
4. `scripts/ark-migrate-jsonl-to-sqlite.sh` — one-shot importer for existing 44 rows; idempotent (PRIMARY KEY blocks duplicates)
5. Update `scripts/ark-verify.sh` Tier 8 checks: replace JSONL grep/wc with sqlite3 queries
6. Self-test: ark-policy.sh test must still pass 16/16
7. Backward-compat: keep policy-decisions.jsonl readable but mark deprecated; new writes go ONLY to SQLite

## Acceptance

- `bash scripts/ark-policy.sh test` exits 0 with all 16 assertions passing against SQLite
- `bash scripts/ark-verify.sh --tier 8` still passes (≥25/25 retained)
- `sqlite3 ~/vaults/ark/observability/policy.db "SELECT count(*) FROM decisions"` returns ≥44 (migrated rows)
- `_policy_log` writes go ONLY to SQLite; JSONL file untouched after migration
- `policy_audit` reads from SQLite

## Risks

- ark-deliver running concurrently during migration could miss writes — mitigated by running migration with no active deliveries (current state)
- WAL mode files (db-shm, db-wal) need `.gitignore` entries

