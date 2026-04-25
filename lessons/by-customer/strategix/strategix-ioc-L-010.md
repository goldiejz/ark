---
id: strategix-ioc-L-010
title: Active breach queues and historical SLA outcomes are different concepts
date_captured: 2026-04-22
origin_project: strategix-ioc
origin_repo: ioc
scope: ["integration", "assurance"]
severity: HIGH
applies_to_domains: ["ioc", "halopsa"]
customer_affected: [strategix]
universal: false
---

## Rule

Never use the historical SLA breach flag by itself to populate an active work queue. Live operational breach means `is_closed=false AND sla_is_breached=true AND sla_data_present=true`. Historical reporting may count closed rows with `sla_is_breached=true`, except rows explicitly excluded from SLA. Ticket detail should distinguish `slaStatus` (live state) from `slaOutcome` (reporting state), so a closed breached ticket reads as closed with a breached historical outcome, not as an active breach requiring action. Reporting code must defensively honour `raw_json.excludefromsla` because old cached rows can retain stale `sla_data_present` / `sla_is_breached` from before the connector learned that flag.

## Trigger Pattern

On `2026-04-22`, ticket #242375 appeared in the Tickets section as breached even though HaloPSA had closed it on `2026-04-13`. Root cause: `/api/v1/drill-down/tickets` derived operational `slaStatus` directly from `ticket_cache.sla_is_breached` without filtering `is_closed=false`. Production D1 had 1,750 closed rows with `sla_is_breached=1`; those rows are valid historical SLA outcomes for MBR/QBR, but invalid live operational breaches.

## Mistake

Source lesson title: "Active breach queues and historical SLA outcomes are different concepts"

## Cost Analysis

- Not specified in source lesson.

## Evidence

[`src/app/api/v1/drill-down/tickets/route.ts`](src/app/api/v1/drill-down/tickets/route.ts), [`src/app/api/v1/drill-down/tickets/compute.ts`](src/app/api/v1/drill-down/tickets/compute.ts), [`src/app/api/v1/tickets/[id]/route.ts`](src/app/api/v1/tickets/[id]/route.ts), [`src/lib/sla-reporting.ts`](src/lib/sla-reporting.ts)

## Effectiveness

- Not specified in source lesson.

## Cross-Project History

- Not specified in source lesson.

## Related

- [[strategix-ioc-L-001]]
- [[strategix-L-018]]
