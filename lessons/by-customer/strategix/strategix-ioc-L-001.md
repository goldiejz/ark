---
id: strategix-ioc-L-001
title: Centralized RBAC only works if write routes actually use it
date_captured: 2026-04-08
origin_project: strategix-ioc
origin_repo: ioc
scope: ["RBAC", "security", "assurance"]
severity: CRITICAL
applies_to_domains: ["*"]
customer_affected: [strategix]
universal: true
---

## Rule

- **Always** for any route that mutates platform behavior, use centralized role enforcement via `requireRole(...)`, not just `session?.user` existence checks.
- **Never** assume a route is protected by virtue of requiring authentication. Authenticated != authorized.
- **Always** require adversarial audit passes that specifically check "every write route uses centralized RBAC".

## Trigger Pattern

Audit found authenticated-user write access on correlation rules without checking centralized role enforcement. A user with a valid session could mutate rule state as long as they were logged in — no role-based gate.

## Mistake

Conflating authentication (user is logged in) with authorization (user has permission for this action). An authenticated user is not an authorized admin.

## Cost Analysis

- **Estimated cost to ignore:** Privilege escalation risk, untraceable rule mutations, potential data corruption by unauthorized users.
- **How many projects paid for this lesson:** 1 (strategix-ioc audit baseline, 2026-04-08).
- **Prevented by this lesson:** Mandatory RBAC enforcement on every write route.

## Evidence

- Audit baseline: 2026-04-08, IOC security audit
- File: `src/app/api/v1/intelligence/rules/[id]/route.ts` line 21

## Effectiveness

- **Violations since capture:** 0 (ioc audit cycle enforces this)
- **Prevented by this lesson:** Audit-based enforcement across all IOC routes
- **Last cited:** 2026-04-22

## Related

- Part of: [[doctrine/shared-conventions#RBAC-Discipline]]
- Sibling to: [[strategix-L-018]], [[strategix-L-025]]
- Enforced by: IOC security audit, post-commit validation

---

*Captured 2026-04-08 during strategix-ioc baseline audit*
