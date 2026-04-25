---
id: strategix-servicedesk-L-002
title: Phase 1 is pitch-ready, not operationally-ready
date_captured: 2026-04-22
origin_project: strategix-servicedesk
origin_repo: servicedesk
scope: ["process", "delivery"]
severity: HIGH
applies_to_domains: ["*"]
customer_affected: [strategix]
universal: true
---

## Rule

- **Always** describe Phase 1 as "prototype", "pitch build", or "pitch-ready". Never "shipped", "live", "in production", or "operational".
- **Always** name deferred capabilities explicitly when demoing or pitching (Graph, Azure AD SSO, email-to-ticket, ITIL breadth, CMDB, KB, scheduled reports).
- **Never** use demo fixtures to mask unimplemented behaviour. If a demo beat requires fake data to work, it fails the ALPHA gate and is not demoed.
- **Always** record Phase 1 closure against the seven ALPHA criteria with evidence before marking Phase 1 done in `STATE.md`.


## Trigger Pattern

User directive at scope-lock: _"we are going to build this prototype in 1 week"_ and _"we just need to prove the concept"_.

## Mistake

Phase 1 "pitch-ready" scope being conflated with "ready for internal rollout" or "production" in later conversations, demos, or commit messages. This would overstate the platform's state and erode the trust needed to eventually replace HaloPSA.

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
