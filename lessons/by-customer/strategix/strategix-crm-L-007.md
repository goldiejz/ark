---
id: strategix-crm-L-007
title: role gates on both sides of the network must share one source of truth
date_captured: 2026-04-20
origin_project: strategix-crm
origin_repo: crm
scope: ["revops", "governance"]
severity: CRITICAL
applies_to_domains: ["*"]
customer_affected: [strategix]
universal: true
---

## Rule

One named role list per access concern, in a shared module (here `src/lib/constants.ts > APPROVAL_ROLES`), used verbatim by both the server (`requireRole(...APPROVAL_ROLES)`) and the client (`APPROVAL_ROLES.includes(role)`). Never hand-write a role-literal chain (`role === 'admin' || role === 'finance'...`) for an access concern that has a server-side counterpart. If the shared list has to vary between server and client (rare), say so explicitly with two named constants and a comment pinning the relationship.

## Trigger Pattern

Same Codex review found that the backend's `APPROVAL_ROLES` list (`admin`, `finance_executive`, `finance`, `executive`) did not match the frontend's `canApprove` check on `ProductsPage.tsx` (`admin`, `finance_executive`, `finance` — executive missing). After retiring the duplicate products API, `/api/quotes/pending-approval` was the only in-app queue, so an `executive` was server-authorised but UI-dead-ended: backend told them yes, no page gave them the action.

## Mistake

Hand-written role arrays on either side of the network boundary. Every independently-maintained array drifts: the instant someone adds a role on one side, the other side keeps the old gate. The drift is invisible to typecheck because each side's array is independently well-typed.

## Cost Analysis

- Not specified in source lesson.

## Evidence

- Origin: `strategix-crm/tasks/lessons.md`

## Effectiveness

- Not specified in source lesson.

## Cross-Project History

- Not specified in source lesson.

## Related

- [[strategix-crm-L-001]]
- [[strategix-L-025]]
