---
finding_id: strategix-implementation-drift-001
source: strategix-servicedesk
audit_ids: [dry-run, portal-timesheet-approval-implementation, portal-timesheet-approval-audit, pass1f-merge, day-c-report, timesheet-report, day-c-implementation, day-c-phase2-sync, problem-management-implementation, problem-management-refactor, problem-management-deep]
scope: implementation-drift
verdict: MIXED
blocks_merge: false
severity: MEDIUM
pattern: compute-layer design inconsistencies across Phase 1 features
---

## Summary

11 implementation audits reveal recurring drift patterns in Phase 1 feature implementations (portal timesheet approval, day-c reporting, problem management compute layers). Common issues: route/compute split discipline, error handling gaps, state transition validation, event emission consistency.

## Recurring Pattern 1: Route/Compute Split Inconsistency

**Issue:** Route layers sometimes contain business logic that belongs in compute; compute layers sometimes lack validation that should happen at route boundary.

**Example (portal timesheet approval):**
- Route handler does signature validation (belongs in compute)
- Compute layer lacks state-transition checks (missing from boundary)

**Fix:** Move business logic to compute; keep route thin and focused on HTTP semantics.

**Governing lesson:** L-021—Route/compute split discipline; CLAUDE.md Architecture Conventions.

## Recurring Pattern 2: Event Emission Gaps

**Issue:** Some state mutations (time-entry approval, timesheet submit) do not emit corresponding events. Integration surface lacks signal.

**Fix:** Every mutable operation on tickets, time_entries, timesheets must emit typed event to queue.

**Governing lesson:** L-022—Event emission on mutations is non-negotiable for integration surface.

## Recurring Pattern 3: State Transition Validation Missing

**Issue:** State machines (ticket lifecycle, timesheet approval workflow) sometimes lack guard checks at transitions. Example: timesheet can move to "approved" without verifying all time entries are locked.

**Fix:** Compute layer must validate state transition preconditions before applying mutation.

**Governing lesson:** L-023—State machine discipline; document valid transitions; enforce guards.

## Recurring Pattern 4: Error Handling Asymmetry

**Issue:** Some routes throw HTTP 500 on application errors; others return 400 with validation message. Inconsistent error vocabulary.

**Fix:** Establish error taxonomy (client fault vs server fault), map compute-layer exceptions to HTTP status consistently.

**Governing lesson:** New lesson candidate: "Error handling must be consistent across all routes; use error taxonomy to map exceptions to HTTP codes."

## Cross-Repo Relevance

**Universal pattern:** As Phase 1 features accumulate compute layers, inconsistency increases. By Phase 2, 3-4 different "route/compute" patterns are in use; new developers copy the wrong one.

**Cost if ignored:** Refactoring storm in Phase 2 when inconsistency is discovered; higher bug rate due to missing validations; integration surface unreliable (missing events).

**Prevention:**
1. Code review checklist: "Route layer thin? Compute layer complete? Events emitted? State transitions guarded?"
2. Pre-merge gate scans for event emission on all mutations
3. Architecture documenting canonical route/compute/event pattern with examples

## Findings Files

- `dry-run-audit.md`
- `portal-timesheet-approval-implementation.md`
- `portal-timesheet-approval-audit.md`
- `pass1f-merge-audit.md`
- `day-c-report-audit.md`
- `timesheet-report-audit.md`
- `day-c-implementation-audit.md`
- `day-c-phase2-sync-audit.md`
- `problem-management-implementation-audit.md`
- `problem-management-refactor-audit.md`
- `problem-management-deep-audit.md`

**Total coverage:** 11 Phase 1 feature implementations, all landing design/implementation briefs.

## Next Action

**Phase 2 planning:** Synthesize route/compute/event pattern into canonical document + architecture diagrams. Use this summary to guide Phase 2 implementation discipline.
