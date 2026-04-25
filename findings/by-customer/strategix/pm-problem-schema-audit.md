---
finding_id: strategix-schema-002
source: strategix-servicedesk
audit_id: pm-problem-schema-audit
audit_date: 2026-04-24
scope: schema-drift
verdict: PARTIAL
blocks_merge: false
severity: MEDIUM
origin_issue: RBAC inheritance breadth and priority nullability ambiguity
---

## Summary

PM/Problem schema introduces new role inheritance breadth (manager roles now inherit STAFF globally) and leaves `problems.priority` nullability intent unresolved.

## Key Finding 1: RBAC Inheritance Breadth

**Verdict:** NEEDS-CLARIFICATION

Manager roles (`project_manager`, `team_manager`, `problem_manager`) now inherit `STAFF` globally. Solves `/app/*` 403 but grants full staff capabilities to fine-grained roles.

**Design question:** Is `ROLE_PERMISSIONS` (fine-grained capability set) aspirational schema for Phase 2, or should it be wired now with a new `requirePermission()` guard?

**Recommendation:** Do not block branch merge. Resolve intent before compute layer written. Document decision in `rbac.ts` comment.

## Key Finding 2: Priority Nullability Ambiguity

**Verdict:** NEEDS-CLARIFICATION

`problems.priority` column has `is null or` clause in check constraint but intent is unclear. Should priority be required for all Problems, or optional until triage?

**Recommendation:** User decision required before compute layer dispatch. Document chosen intent in schema comment.

## Related Lessons

- L-018: RBAC enum completeness—every new role must enumerate every `requireRole()` call-site
- L-021: Zod at boundaries validates problem creation payloads

## Cross-Repo Relevance

**Universal pattern:** RBAC drift occurs when new roles added without full-call-site audit. Priority/status nullability decisions must be explicit, not silent.

**Cost if ignored:** Hidden permission escalation (manager can do full staff ops); compute-layer re-work if nullability intent changes.
