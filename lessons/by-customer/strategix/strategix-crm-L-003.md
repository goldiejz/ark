---
id: strategix-crm-L-003
title: D1 is stricter than vanilla SQLite in three specific ways that bit this session
date_captured: 2026-04-19
origin_project: strategix-crm
origin_repo: crm
scope: ["revops", "governance"]
severity: HIGH
applies_to_domains: ["*"]
customer_affected: [strategix]
universal: true
---

## Rule

- **FK validation at CREATE TABLE time:** prepend `PRAGMA foreign_keys=OFF;` to any export-import or table-recreate file.
- **No `BEGIN TRANSACTION` / `SAVEPOINT`** in `wrangler d1 execute --file`. Strip transaction wrappers; D1 wraps each statement itself.
- **`schema_migrations` is not authoritative** — many migrations don't self-record. Confirm column/table existence via `pragma table_info(...)` or `SELECT name FROM sqlite_master`, not by reading the migrations table.

## Trigger Pattern

Multiple D1 errors during the rename: forward FK references in export ("no such table: rate_cards"), `BEGIN TRANSACTION` rejected ("use state.storage.transaction()"), and `schema_migrations` table only tracked 5 of 21 migrations.

## Mistake

Treated D1 as a transparent SQLite layer. It isn't.

## Cost Analysis

- Not specified in source lesson.

## Evidence

- Origin: `strategix-crm/tasks/lessons.md`

## Effectiveness

- Not specified in source lesson.

## Cross-Project History

- Not specified in source lesson.

## Related

- [[strategix-crm-L-001]]
- [[strategix-L-025]]
