---
id: strategix-ioc-L-002
title: “Secrets are not in D1” must be proven, not assumed
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

Secret inventory documents must be derived from schema and write paths, not intention.

## Trigger Pattern

Audit found connector credentials persisted in plaintext D1 rows.

## Mistake

Source lesson title: "“Secrets are not in D1” must be proven, not assumed"

## Cost Analysis

- Not specified in source lesson.

## Evidence

[`src/db/schema.ts`](src/db/schema.ts#L383), [`src/app/api/v1/admin/integrations/route.ts`](src/app/api/v1/admin/integrations/route.ts#L90)

## Effectiveness

- Not specified in source lesson.

## Cross-Project History

- Not specified in source lesson.

## Related

- [[strategix-ioc-L-001]]
- [[strategix-L-018]]
