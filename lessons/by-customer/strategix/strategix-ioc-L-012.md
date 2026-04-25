---
id: strategix-ioc-L-012
title: SQL cutoff comparison on JSON-extracted timestamps needs `json_valid` + time-aware casting
date_captured: 2026-04-21
origin_project: strategix-ioc
origin_repo: ioc
scope: ["integration", "assurance"]
severity: HIGH
applies_to_domains: ["*"]
customer_affected: [strategix]
universal: true
---

## Rule

When filtering on a JSON-extracted timestamp column in SQLite: (1) always guard `json_extract` with `CASE WHEN json_valid(x) THEN json_extract(x, '$.field') ELSE NULL END` — AND short-circuit is not contractually guaranteed by SQL; (2) for time-based comparisons wrap both sides in `strftime('%Y-%m-%d %H:%M:%f', ...)` to preserve sub-second precision and normalize formats; plain `datetime()` truncates. The pattern: `strftime('%Y-%m-%d %H:%M:%f', CASE WHEN json_valid(x) THEN json_extract(x, '$.field') END) > strftime('%Y-%m-%d %H:%M:%f', $cutoff)`. Long-term: if the column becomes a hot filter path, migrate it to a first-class typed column so it can be indexed.

## Trigger Pattern

TQR automation rounds 10–12 on 2026-04-21. First draft used `json_extract(raw_json, '$.dateclosed') > $cutoff` which (a) raises on a single corrupt JSON row and aborts the whole WHERE, and (b) compares strings lexicographically, so "2026-04-21T20:00:00+00:00" (same instant, different format) mis-orders vs "2026-04-21T20:00:00.000". Even `datetime()` wrapping truncates to whole seconds, dropping millisecond precision on a no-backfill forward-only path.

## Mistake

Source lesson title: "SQL cutoff comparison on JSON-extracted timestamps needs `json_valid` + time-aware casting"

## Cost Analysis

- Not specified in source lesson.

## Evidence

[`src/lib/tqr/batch.ts`](src/lib/tqr/batch.ts) (discovery WHERE predicate).

## Effectiveness

- Not specified in source lesson.

## Cross-Project History

- Not specified in source lesson.

## Related

- [[strategix-ioc-L-001]]
- [[strategix-L-018]]
