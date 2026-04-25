---
id: strategix-ioc-L-005
title: `onConflictDoNothing()` does not mean “stored”
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

Counters must reflect actual DB effects, not attempted writes.

## Trigger Pattern

Event pipeline increments `stored` even when an insert is skipped by conflict.

## Mistake

Source lesson title: "`onConflictDoNothing()` does not mean “stored”"

## Cost Analysis

- Not specified in source lesson.

## Evidence

[`src/services/event-pipeline.ts`](src/services/event-pipeline.ts#L146)

## Effectiveness

- Not specified in source lesson.

## Cross-Project History

- Not specified in source lesson.

## Related

- [[strategix-ioc-L-001]]
- [[strategix-L-018]]
