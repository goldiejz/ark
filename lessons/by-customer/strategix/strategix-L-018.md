---
id: strategix-L-018
title: Centralised RBAC — inline role arrays forbidden
date_captured: 2026-04-24
origin_project: strategix-servicedesk
origin_repo: servicedesk
scope: ["RBAC", "security", "planning/coding"]
severity: CRITICAL
applies_to_domains: ["*"]
customer_affected: [strategix]
universal: true
---

## Rule

- **Always** define all roles and permission constants in a single source of truth (`src/lib/rbac.ts`, `src/lib/auth-guards.ts`, or `functions/api/middleware/rbac.ts` depending on repo).
- **Always** use `requireRole(...)` from the centralised module at every route that gates access.
- **Never** inline role arrays in routes or components (e.g., `['staff', 'admin'].includes(role)`).
- **Always** cross-check every existing `requireRole(...)` call-site when adding a new role — ensure the role inherits or is explicitly excluded from each guard.

## Trigger Pattern

**Phase 2 schema brief §6** added three new roles (`project_manager`, `team_manager`, `problem_manager`) with inheritance specified only upward ("admin inherits all three; staff does not inherit"), silent on whether the manager roles inherit `staff`. Codex followed literally — each manager role inherited only itself. Intersected with the staff-app guard `requireRole([ROLES.STAFF, ROLES.ADMIN])` at `src/features/app-route-auth.ts:32`, this locked any user whose sole role was a manager out of `/app/*` — tickets, time-entries, timesheets, dashboard, all 403. Schema / convention / tenant-scoping adversarial lenses did not catch it; none was scoped to "existing-guards-vs-new-roles". Codex stop-hook caught it on a third pass.

## Mistake

Treating role inheritance as a property of the role definition in isolation. A role's effective meaning is the intersection of `ROLE_INHERITANCE` with every `requireRole()` call-site. A new role can look self-consistent in `rbac.ts` while silently locking users out of core surfaces.

## Cost Analysis

- **Estimated cost to ignore:** Silent user lockout, 403 errors across critical flows, 2-4 days to triage and fix (first assumption: it's a token issue; second: auth configuration; third: RBAC inheritance).
- **How many projects paid for this lesson:** 1 (strategix-servicedesk, fixed in commit f015182).
- **Prevented by this lesson (estimate):** 3-5 per project that follows the rule.

## Evidence

- Commit that surfaced it: `f015182` (added regression tests for manager role inheritance)
- Stop-hook finding: `L-018: Silent RBAC lockout when new role inheritance is incomplete`
- Related to: [[strategix-L-019]] (multi-tenant RBAC variant), [[universal-patterns#RBAC-Lockout-Cascade]]

## Effectiveness

- **Violations since capture:** 1 (strategix-crm re-duplicated the pattern with `CURVE_WRITE_ROLES` despite lesson existing — caught in L-025 sub-rule and fixed by extracting roles to constants.ts).
- **Prevented by this lesson (observed):** 1 incident in servicedesk phase 2 schema brief.
- **Last cited:** 2026-04-24

## Cross-Project History

- **Strategix (origin):** Discovered 2026-04-24, prevented lockout incident in phase 2.
- **Strategix CRM (recurrence):** 2026-04-21, re-duplicated with `CURVE_WRITE_ROLES` — caught by adversarial review (L-025), fixed same day.
- **Strategix IOC:** Not yet observed; design uses centralised `auth-guards.ts` consistently.

## Related

- Prevents anti-pattern: "Silent RBAC inheritance"
- Part of: [[doctrine/shared-conventions#RBAC-Discipline]]
- Variant: [[strategix-L-019]] — Multi-tenant RBAC scoping
- Sibling lesson: [[strategix-L-025]] — Role arrays must cite shared constants, not hand-write

---

*Captured 2026-04-24 during Codex stop-hook review of phase 2 schema brief*
