---
id: strategix-ioc-L-008
title: HaloPSA `/api/Tickets?open_only=true` does not know when a CR workflow closes
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

Do not assume `/api/Tickets?open_only=true` is the authoritative view of what is open in HaloPSA. Change requests (and anything workflow-driven) can complete via a workflow step without updating the ticket's `status_id` or `inactive` flag that `open_only` filters on. Detecting closure requires richer fetch params (`includedetails`) or a separate CR endpoint — `open_only` cannot be relied on as a completeness guarantee for terminal-state detection. Related: `fetchClosedTickets` passes `open_only: "false"` which means "don't filter by open-flag", not "closed only", so it is also not a valid source of truth for terminal state.

## Trigger Pattern

Same #241354 investigation. The HaloPSA UI reported the CR as Closed with a 2026-04-15 close date and closer, but the `/api/Tickets?open_only=true` endpoint kept returning it with `status_id=1`, `inactive=false`, and no `dateclosed`/`closed_date` on the payload. The ticket was being re-synced to IOC as "open" every cron tick.

## Mistake

Source lesson title: "HaloPSA `/api/Tickets?open_only=true` does not know when a CR workflow closes"

## Cost Analysis

- Not specified in source lesson.

## Evidence

[`src/connectors/halopsa/tickets.ts`](src/connectors/halopsa/tickets.ts#L6), [`src/connectors/halopsa/tickets.ts`](src/connectors/halopsa/tickets.ts#L37)

## Effectiveness

- Not specified in source lesson.

## Cross-Project History

- Not specified in source lesson.

## Related

- [[strategix-ioc-L-001]]
- [[strategix-L-018]]
