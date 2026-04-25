---
id: strategix-servicedesk-L-003
title: Microsoft Graph and Azure AD deferred by user direction
date_captured: 2026-04-22
origin_project: strategix-servicedesk
origin_repo: servicedesk
scope: ["process", "delivery"]
severity: HIGH
applies_to_domains: ["servicedesk"]
customer_affected: [strategix]
universal: false
---

## Rule

- **Never** include Graph, Azure AD SSO, or calendar ingestion work in Phase 1 without explicit user re-authorisation.
- **Always** honour the activity-dwell-based nudge as the Phase 1 substitute for calendar-driven proposal — it's functionally honest and uses data the platform already owns.
- **Always** position Graph and SSO as Phase 2 in demo narration, not Phase 1 omissions.


## Trigger Pattern

User directive during scope negotiation: _"drop calendar ingestion for now and Microsoft Graph integrations. We just need to prove the concept and i will explain what is still to be done"_.

## Mistake

Re-adding Graph or Azure AD work into Phase 1 because "it's nearly done anyway" or "the pitch would be stronger with it". The user has chosen to narrate these as roadmap items in the pitch rather than build them in Phase 1.

## Cost Analysis

- Not specified in source lesson.

## Evidence

- Origin: `strategix-servicedesk/tasks/lessons.md`

## Effectiveness

- Not specified in source lesson.

## Cross-Project History

- Not specified in source lesson.

## Related

- [[strategix-L-001]]
- [[strategix-L-023]]
