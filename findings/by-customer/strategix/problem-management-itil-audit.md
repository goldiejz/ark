---
finding_id: strategix-rbac-001
source: strategix-servicedesk
audit_id: problem-management-itil-audit
audit_date: 2026-04-25
scope: rbac-lockout
verdict: PARTIAL
blocks_merge: false
severity: MEDIUM
origin_issue: RBAC drift in Problem Management feature; manager roles over-permissioned
---

## Summary

Problem Management ITIL implementation identified RBAC drift: manager roles inherit STAFF globally, enabling access to unintended operations (ticket creation, timesheet submission) that should be guarded by fine-grained `ROLE_PERMISSIONS`.

## Key Finding: RBAC Inheritance Breadth

**Verdict:** NEEDS-CLARIFICATION

Three new manager roles (`project_manager`, `team_manager`, `problem_manager`) inherit `STAFF` for staff-app access, but `ROLE_PERMISSIONS` (fine-grained capability set) is not enforced by `requireRole()` guards.

**Problem:**
- `staffAppOnly()` guard checks `requireRole([STAFF, ADMIN])` only
- Manager roles pass because they inherit STAFF
- But `ROLE_PERMISSIONS` defines narrower capabilities that are never enforced
- Result: `team_manager` can create tickets and timesheets (unintended side-effects)

**Recommendation:** 
1. Decide: Is `ROLE_PERMISSIONS` immediate enforcement or Phase 2 aspirational?
2. If immediate: Wire a `requirePermission()` guard factory
3. If Phase 2: Document in code that `ROLE_PERMISSIONS` is future; do not silently ignore

Do not block merge. Resolve before compute layer written.

## Related Lessons

- L-018: RBAC enum completeness—every new role must audit every `requireRole()` call-site
- L-020: Manager roles should not inherit full STAFF authority; use permission checks instead

## Cross-Repo Relevance

**Universal pattern:** RBAC lockout occurs when new roles added without full permission audit. Fine-grained permission layers (like `ROLE_PERMISSIONS`) become "dead code" if not enforced by guards.

**Affected projects:**
- strategix-servicedesk (source)
- strategix-revops (commission approvers, deal managers with similar inheritance risk)
- strategix-ioc (MSP engineers, account managers with narrower scope)

**Cost if ignored:** Hidden permission escalation; users accessing operations outside their domain; audit trail shows STAFF operations that should be domain-specific.

**Prevention:** 
1. Pre-commit hook validates every new role is used in at least one `requireRole()` call
2. L-018 violation detection: grep for unused roles in `ROLE_PERMISSIONS` vs actual `requireRole()` guards
3. Code review checklist: "Does every new role have a corresponding guard check?"
