---
id: strategix-ioc-L-004
title: Deterministic IDs can silently defeat time-window dedup
date_captured: 2026-04-08
origin_project: strategix-ioc
origin_repo: ioc
scope: ["integration", "assurance"]
severity: HIGH
applies_to_domains: ["*"]
customer_affected: [strategix]
universal: true
---

## Rule

If recurrence should create a new lifecycle record, ID generation must include windowing or versioning.

## Trigger Pattern

Signal writers query a 60-minute window, then reuse the same ID forever with `onConflictDoUpdate`.

## Mistake

Source lesson title: "Deterministic IDs can silently defeat time-window dedup"

## Cost Analysis

- Not specified in source lesson.

## Evidence

[`src/services/event-pipeline.ts`](src/services/event-pipeline.ts#L315), [`src/services/correlation-engine.ts`](src/services/correlation-engine.ts#L141)

## Effectiveness

- Not specified in source lesson.

## Cross-Project History

- Not specified in source lesson.

## Related

- [[strategix-ioc-L-001]]
- [[strategix-L-018]]
