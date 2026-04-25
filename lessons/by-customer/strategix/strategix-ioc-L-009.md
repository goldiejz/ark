---
id: strategix-ioc-L-009
title: HaloPSA `dateclosed` is the only reliable closure signal — not `inactive`, not `open_only`
date_captured: 2026-04-21
origin_project: strategix-ioc
origin_repo: ioc
scope: ["integration", "assurance"]
severity: HIGH
applies_to_domains: ["ioc", "halopsa"]
customer_affected: [strategix]
universal: false
---

## Rule

For HaloPSA, treat `dateclosed` (with the "0001-01-01T00:00:00" sentinel meaning "never") as THE closure signal. Do NOT trust `inactive`, do NOT trust `open_only`, do NOT trust `status_id` mapping alone (the tenant's `status_id=9` "Closed" may not be in the status_mapping table, and relying on enum membership conflates workflow state with lifecycle state). On every fetch of HaloPSA tickets, send `includedetails=true` AND set `isClosed = true` whenever `dateclosed` is a real timestamp. This works uniformly across regular tickets and workflow-driven CRs — no type-specific code needed.

## Trigger Pattern

On `2026-04-21`, reconciled three stuck tickets via a per-ticket fetch against `/api/Tickets/{id}?includedetails=true`. All three — two regular tickets (#253464 Printer, #242375 Azure quota) and one change request (#241354 testtttt) — showed the same pattern when closed:
```
status_id:         9
inactive:          false           ← unchanged, useless signal
dateclosed:        "2026-03-31T13:52:55.487"  ← populated on closure
onhold:            false
```
Meanwhile, `/api/Tickets?open_only=true` kept returning these tickets briefly after closure (regular ticket case) or indefinitely (CR workflow closure case) until HaloPSA's internal process eventually dropped them from the open-only view. The `fetchAllOpenTickets` call did not request `includedetails=true`, so `dateclosed` was not even in the payload IOC received — closure was invisible.

## Mistake

Source lesson title: "HaloPSA `dateclosed` is the only reliable closure signal — not `inactive`, not `open_only`"

## Cost Analysis

- Not specified in source lesson.

## Evidence

[`src/services/ticket-sync.ts`](src/services/ticket-sync.ts) (`isTicketClosedFromPayload`), [`src/connectors/halopsa/tickets.ts`](src/connectors/halopsa/tickets.ts#L6)

## Effectiveness

- Not specified in source lesson.

## Cross-Project History

- Not specified in source lesson.

## Related

- [[strategix-ioc-L-001]]
- [[strategix-L-018]]
