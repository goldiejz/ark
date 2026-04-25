---
id: strategix-ioc-L-003
title: KV `get` then `put` is not a distributed lock
date_captured: 2026-04-08
origin_project: strategix-ioc
origin_repo: ioc
scope: ["integration", "assurance"]
severity: CRITICAL
applies_to_domains: ["*"]
customer_affected: [strategix]
universal: true
---

## Rule

If two requests can both observe “unlocked” before either writes, the lock is not real.

## Trigger Pattern

HaloPSA sync lock uses a check-then-set pattern.

## Mistake

Source lesson title: "KV `get` then `put` is not a distributed lock"

## Cost Analysis

- Not specified in source lesson.

## Evidence

[`src/app/api/v1/cron/halopsa-sync/route.ts`](src/app/api/v1/cron/halopsa-sync/route.ts#L28), [`src/app/api/v1/sync/route.ts`](src/app/api/v1/sync/route.ts#L28)

## Effectiveness

- Not specified in source lesson.

## Cross-Project History

- Not specified in source lesson.

## Related

- [[strategix-ioc-L-001]]
- [[strategix-L-018]]
