---
id: strategix-crm-L-008
title: mutation errors without visible UI become silent dead-ends
date_captured: 2026-04-20
origin_project: strategix-crm
origin_repo: crm
scope: ["revops", "governance"]
severity: HIGH
applies_to_domains: ["*"]
customer_affected: [strategix]
universal: true
---

## Rule

Every TanStack Query `useMutation` that targets a write whose backend may return 4xx for reasons the user can act on (stale revision, validation failure, conflict) must have an `onError` handler that (a) surfaces the server message in a visible UI element (banner/toast/inline text) and (b) invalidates the related query keys so the user's next attempt is keyed to fresh server state. Mute-success patterns are OK only for fire-and-forget writes where failure is no-worse-than-not-trying. Decision surfaces are never fire-and-forget.

## Trigger Pattern

Codex adversarial-review on the revision-aware CAS commit found that `MarginApprovalBanner` had only `onSuccess` — any 409 `Stale decision` or other server error was swallowed: no rendered error, no queue refetch. An approver who clicked after a sales edit would get no explanation and would keep clicking the same stale token until the default `staleTime` (30s) expired. The tighter CAS made the race SAFER but the UX WORSE — the backend is doing its job while the UI silently pretends nothing happened.

## Mistake

Treating the happy-path mutation as sufficient. When a backend adds a new 4xx path (here 409), the frontend mutation handling has to gain a matching branch. `onSuccess` alone leaves the user stuck on the exact class of failure the new check was designed to catch.

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
