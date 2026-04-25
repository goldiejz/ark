---
finding_id: strategix-schema-001
source: strategix-servicedesk
audit_id: phase2-schema-audit
audit_date: 2026-04-24
scope: schema-drift
verdict: PARTIAL
blocks_merge: false
severity: MEDIUM
origin_issue: work_packages table missing soft-delete affordance
---

## Summary

Phase 2 PM/Problem schema audit identified two design findings: RBAC inheritance breadth (partially addressed in recent commit) and soft-delete omission on `work_packages` and `wp_activities` tables.

## Key Finding: Soft-Delete Omission

**Verdict:** AGREE

Tables `work_packages` and `wp_activities` lack `deleted_at` column, violating repo soft-delete convention.

**Evidence:**
- `src/db/schema.ts`: no `deletedAt` field in workPackages or wpActivities definitions
- Convention: `tickets`, `time_entries`, `timesheets` all carry soft-delete
- WPs carry billable history + acceptance criteria—deleting hard removes audit trail

**Recommendation:** Add `deleted_at` before compute layer written. Not a merge blocker for schema-only slice.

## Related Lessons

- L-021: CLAUDE.md Architecture Conventions (soft-delete principle)
- L-018: RBAC enum completeness

## Cross-Repo Relevance

**Universal pattern:** Every mutable business table needs soft-delete audit trail. Schema drift occurs when new tables added without it.

**Affected projects:**
- strategix-servicedesk (source)
- strategix-revops (future Problem integration)
- strategix-ioc (future SLA/incident correlation)

**Cost if ignored:** Lost audit trail on work package deletion; billing disputes; non-repudiable state gaps.
