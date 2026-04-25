---
id: strategix-crm-L-006
title: state transitions need compare-and-swap, not read-then-write
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

For any finite state transition (approval queue, workflow status, lock acquisition, one-shot provisioning), compose the transition into a single SQL statement with the expected source state in the `WHERE` clause: `UPDATE ... SET <new state> WHERE id = ? AND <column> = <expected prior state>`. Inspect the row count (`result.meta?.changes` on D1) and fail with 409 when zero rows change. Only write the audit record *after* a confirmed write; a failed CAS must not leave a successful-audit trail. The pre-UPDATE `SELECT` stays as a source of good error messages for 404 / non-pending / self-approval, but it is not the safety barrier — the CAS is.

## Trigger Pattern

Codex adversarial-review of the A4 approval unification (2026-04-20) found that both `/api/quotes/:id/approve-margin` and `/api/quotes/:id/reject-margin` did a `SELECT ... margin_approval_status = 'pending'` check, then an unconditional `UPDATE ... WHERE id = ?`. Two approvers hitting the same quote near-simultaneously could both pass the read-time check and both `UPDATE` — silently overwriting each other with no error, and double-writing the audit trail. Widening `APPROVAL_ROLES` to include `finance` enlarged the pool of potential colliding actors, so the race became more likely right as more roles gained access.

## Mistake

Treating a precondition read as a gate instead of as a best-effort error message. Read-then-write on a finite state transition is last-write-wins by construction — the read-time check only affects the *response body*, not the *invariant*.

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
