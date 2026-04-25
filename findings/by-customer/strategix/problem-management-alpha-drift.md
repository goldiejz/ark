---
finding_id: strategix-contradiction-001
source: strategix-servicedesk
audit_id: problem-management-alpha-drift
audit_date: 2026-04-25
scope: contradiction
verdict: PARTIAL
blocks_merge: false
severity: MEDIUM
origin_issue: Problem Management feature gates vs Alpha specification misalignment
---

## Summary

Problem Management implementation drifts from Alpha GATE specification. Feature ships in Phase 2 per ROADMAP.md, but design decisions (RBAC inheritance, priority nullability) contradict Phase 1 Alpha control closure expectation.

## Key Finding: Gate Specification Contradiction

**Claim:** Problem Management (ITIL type beyond Incident) is Phase 2 scope per `.planning/ROADMAP.md`. Alpha gate (Phase 1) does not include Problems. Yet implementation is landing on feature branches being reviewed against Alpha completion criteria.

**Evidence:**
- `.planning/ROADMAP.md`: "Phase 2: ITIL types beyond Incident. Service Request, Change, Problem deferred"
- `.planning/ALPHA.md`: Pitch-ready criteria do not mention Problems
- Feature branch `feat/pm-problem-schema`: advancing Problem schema, compute, routing
- Audit review: checked against current ALPHA gate, found contradictions

**Recommendation:**
1. Clarify: Is Problem Management actually Phase 1.5 or Phase 2?
2. If Phase 2: Defer feature branch merge until Phase 2 planning gate
3. If Phase 1.5: Update `.planning/ROADMAP.md` and `.planning/ALPHA.md` explicitly
4. Do not merge Phase 2 work into Phase 1 branch without explicit gate update

## Related Lessons

- L-005: Gate definition must be explicit and stable before implementation lands
- L-006: Contradiction pass before merge: verify feature scope against ROADMAP and ALPHA

## Cross-Repo Relevance

**Universal pattern:** Phase scope drift occurs when implementation lands without explicit gate alignment. Features that should be deferred appear in current-phase branches, confusing priority and complicating rollback.

**Cost if ignored:** Alpha gate becomes ambiguous; reviewers inconsistent about what's in scope; "ready for pitch" claim becomes untrue; rework when real Phase 2 planning happens.

**Prevention:**
1. ROADMAP.md and ALPHA.md must be updated before feature branch created, not after
2. Pre-merge gate: Verify feature commits reference explicit ROADMAP phase; block merge if undeclared
3. Contradiction audit: Every merge does a scope-alignment check against ROADMAP and ALPHA

## Drift Notes

Current drift: Problem Management implementation exists; ROADMAP says Phase 2; ALPHA gate says Phase 1. Contradiction is real and must be resolved before Phase 2 starts.
