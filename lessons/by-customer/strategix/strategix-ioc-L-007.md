---
id: strategix-ioc-L-007
title: HaloPSA `/api/Client` silently omits internal / special-flag clients
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

When a third-party API has a primary-list endpoint (`/api/Client`, `/api/Agent`, etc.) AND ALSO denormalises the same entity name onto per-event payloads (like a ticket's `client_name`), treat the event-level denormalisation as the authoritative fallback source of truth for display. Do not assume the primary-list endpoint returns every entity the system references. The correct sync shape is: (1) authoritative sync from the primary list, (2) post-pass that seeds any entity referenced on an event but missing from the list, using the event-level copy of the name. The test that catches this: a ticket payload referencing a `client_id` not present in the seed of `/api/Client`, followed by a display-layer assertion that the rendered name is NOT "Client {id}".

## Trigger Pattern

On `2026-04-21`, the Wall and drill-down surfaces rendered "Client 12" for 40 open tickets and similar fallbacks for 6 other client ids. Root cause: HaloPSA's `/api/Client` endpoint does not return every client referenced by tickets. In this tenant, at least id=12 (Strategix — the MSP's own organisation) and 6 other customers are absent from the list. Tickets still carry the correct `client_name` on their payload, so IOC never noticed the gap — it just silently fell back to `Client {id}` on the display path.

## Mistake

Source lesson title: "HaloPSA `/api/Client` silently omits internal / special-flag clients"

## Cost Analysis

- Not specified in source lesson.

## Evidence

[`src/connectors/halopsa/clients.ts`](src/connectors/halopsa/clients.ts) (authoritative), [`src/services/ticket-sync.ts`](src/services/ticket-sync.ts) (post-pass `seedMissingClientsFromTickets`)

## Effectiveness

- Not specified in source lesson.

## Cross-Project History

- Not specified in source lesson.

## Related

- [[strategix-ioc-L-001]]
- [[strategix-L-018]]
