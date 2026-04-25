---
id: strategix-L-025
title: Role arrays must cite shared constants, not hand-write
date_captured: 2026-04-21
origin_project: strategix-crm
origin_repo: crm
scope: ["RBAC", "security", "constants"]
severity: CRITICAL
applies_to_domains: ["*"]
customer_affected: [strategix]
universal: true
---

## Rule

- **Always** when a route needs to check roles, use a named constant exported from `src/lib/constants.ts` or the repo's RBAC source module.
- **Never** hand-write role literals (`'admin' || 'finance'`) or duplicate role arrays (`['admin', 'finance_executive']`) in multiple files.
- **Always** grep the diff for `_ROLES`, `canWrite`, `canApprove`, role-literal chains (`role === '...'`) when reviewing any new route + UI pair. Those arrays are the primary source of RBAC drift.
- **Always** have the shared constant paired with at least one test proving both server and client use the same list (or deliberately document why they differ).

## Trigger Pattern

A3 admin UI (`/settings/commercial-rules`, shipped 2026-04-21) re-duplicated the pattern despite [[strategix-L-025.md]] existing — backend had `const WRITE_ROLES = ['admin', 'finance_executive']` while the UI page had `const WRITE_ROLES = new Set(['admin', 'finance_executive'])`. Caught in adversarial review and fixed by extracting `CURVE_READ_ROLES` + `CURVE_WRITE_ROLES` to `src/lib/constants.ts`. The lesson written the day before didn't prevent the regression because nothing actively grep-ed the new surface against existing lessons.

## Mistake

Treating role enforcement as something that can be hand-written at each usage site without central coordination. Each independently-maintained array drifts: the instant someone adds a role on one side, the other side keeps the old gate. The drift is invisible to typecheck because each side's array is independently well-typed. When server RBAC and UI visibility gates diverge, the user sees "approved by backend" but no UI action to exercise that approval.

## Cost Analysis

- **Estimated cost to ignore:** Silent RBAC divergence between server and client, user confusion when backend says yes but UI is dead-ended, unintended privilege escalation or excessive lockout.
- **How many projects paid for this lesson:** 2 (strategix-crm re-duplicated the A3 pattern, caught same day).
- **Prevented by this lesson:** Central constant + grep-on-review discipline stops drift at commit time.

## Evidence

- Commit that surfaced it: A3 admin UI review (2026-04-21), fixed by extracting constants
- Related to: [[strategix-L-018]] (centralised RBAC), [[strategix-L-019]] (multi-tenant variant)
- Grep pattern: `_ROLES`, `canWrite`, `canApprove`, `role === '...'` in diffs

## Effectiveness

- **Violations since capture:** 1 (crm A3, caught in same turn by adversarial review)
- **Prevented by this lesson (observed):** Stops future hand-written role arrays at code-review time
- **Last cited:** 2026-04-21

## Cross-Project History

- **Strategix CRM (origin):** Discovered 2026-04-21, fixed A3 admin UI in same session

## Related

- Prevents anti-pattern: "Hand-written role arrays"
- Part of: [[doctrine/shared-conventions#RBAC-Discipline]]
- Sibling lessons: [[strategix-L-018]] (centralised RBAC), [[strategix-L-019]] (multi-tenant scoping)
- Enforced by: code-reviewer lens "grep for _ROLES and role literals"

---

*Captured 2026-04-21 during strategix-crm A3 admin UI review*
