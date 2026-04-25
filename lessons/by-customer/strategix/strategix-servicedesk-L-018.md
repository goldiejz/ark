---
id: strategix-servicedesk-L-018
title: New RBAC roles must cross-check every existing route guard; silent lockouts are the default failure mode
date_captured: 2026-04-24
origin_project: strategix-servicedesk
origin_repo: servicedesk
scope: ["process", "delivery"]
severity: HIGH
applies_to_domains: ["*"]
customer_affected: [strategix]
universal: true
---

## Rule

- **Always** any brief that adds a role must enumerate every existing `requireRole(...)` call-site and state per new role whether the role must pass each guard. Format: `requireRole([STAFF, ADMIN])` at `/app/*` → PM ✓ TM ✓ ProblemM ✓ (via STAFF inheritance); `requireRole([CUSTOMER])` at `/portal/*` → PM ✗ TM ✗ ProblemM ✗ (by design).
- **Always** when a brief is silent on inheritance, default any product-using role to inherit `STAFF`. A role that does not inherit `STAFF` is a role for a user who will not use the staff app — which must be called out explicitly.
- **Always** when extending RBAC, add a regression test per new role proving the role passes the guards it should and fails the guards it should. `tests/auth/requires-auth.test.ts` is the right place.
- **Always** adversarial review of an RBAC change must include a dedicated "existing-guards-vs-new-roles" lens. If the review has three lenses and none is guard-surface, the change is under-reviewed.
- **Never** ship a new role without running the effective-roles computation against the existing guard set. A role that self-consistent-ly exists but cannot access any app surface is a lockout bomb.
- **Never** accept an overseer response that contains its own lens output inline without at least one `Agent({...})` tool call visible in its transcript. If the transcript shows only Read/Grep/Bash, the hierarchy collapsed — even if the synthesis section is perfect.


## Trigger Pattern

Phase 2 schema brief §6 added three new roles (`project_manager`, `team_manager`, `problem_manager`) with inheritance specified only upward ("admin inherits all three; staff does not inherit"), silent on whether the manager roles inherit `staff`. Codex followed literally — each manager role inherited only itself. Intersected with the staff-app guard `requireRole([ROLES.STAFF, ROLES.ADMIN])` at `src/features/app-route-auth.ts:32`, this locked any user whose sole role was a manager out of `/app/*` — tickets, time-entries, timesheets, dashboard, all 403. Schema / convention / tenant-scoping adversarial lenses did not catch it; none was scoped to existing-guards-vs-new-roles. Codex stop-hook caught it. Fix in `f015182`: each manager role inherits `STAFF`, plus three regression tests.

## Mistake

Treating role inheritance as a property of the role definition in isolation. A role's effective meaning is the intersection of `ROLE_INHERITANCE` with every `requireRole()` call-site. A new role can look self-consistent in `rbac.ts` while silently locking users out of core surfaces, because the test suite and brief review only check what was added, not what the addition changed by subtraction.

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
