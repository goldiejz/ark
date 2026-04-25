---
id: strategix-crm-L-005
title: A control surface must have exactly one state machine
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

A control surface (approval, rate-card, commission, audit, etc.) must have exactly one state machine. If a new, stricter implementation is introduced next to an older one, retire the old one in the same change — delete the routes, delete the client wrappers, delete any referencing UI, and add a test that proves the old routes return 404. If the retirement is too risky to do inline, treat the duplication as a P0 item in `tasks/todo.md` with an explicit closure date, not a standing design artefact. Until then, every mutation via either path is a latent policy bypass via the other path.

## Trigger Pattern

A4 shipped with two concurrently-mounted approval APIs (`/api/products/margin-approvals` and `/api/quotes/*-margin`) operating on the same `quotes` rows but with divergent state machines. The products API toggled a legacy `margin_approval_required` flag; the quotes API owned the richer `margin_approval_status` column. A quote rejected via quotes.ts retained `margin_approval_required = 1` and `margin_approved_by IS NULL`, so it remained visible in the products queue and could be "approved" there without clearing `margin_approval_status = 'rejected'` — a rejected deal could be silently resurrected through the other API. Plus the products PATCH lacked a self-approval guard and had a reject branch that cleared `margin_approval_required` without writing rejection state, letting the quote advance past the platform gate. Role gates diverged too: products allowed plain `finance`; quotes excluded it.

## Mistake

Adding a new, stricter API next to the old one without retiring the old one. Each new Codex finding ("fix the reject-bypass", "add a self-approval guard", "include finance in the queue") kept targeting whichever surface the finding happened to hit, instead of treating the existence of two surfaces as the root defect. Tests grew on both sides in parallel, reinforcing the duplication.

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
