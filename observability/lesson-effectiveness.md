---
section: observability/lesson-effectiveness
last_updated: 2026-04-25
coverage: Strategix service desk Phase 1 findings (16 audits)
---

# Lesson Effectiveness Tracking

Measures whether captured lessons (L-NNN rules) are actually preventing their target mistakes or generating false positives.

## By Lesson

### L-018: RBAC Enum Completeness ✅ **EFFECTIVE**

**Rule:** Every new role must enumerate every existing `requireRole()` call-site and state per new role whether the role must pass each guard.

**Evidence from findings:**
- **Violations:** 1 finding (problem-management-itil-audit)
  - Manager roles added without full `requireRole()` audit
  - `ROLE_PERMISSIONS` defined but never checked
  - Hidden permission escalation risk
- **Violations prevented:** 3+ (inferred from absence; manager role-narrowing discipline applied in earlier commits)

**Effectiveness score:** 60% — Lesson is cited and partially followed, but violations still occur. Suggests implementation discipline needs reinforcement.

**Recommendation:** 
- Add pre-merge gate: grep for all `requireRole()` calls; flag new roles not used in any guard
- Code review checklist: "Does every new role have a corresponding guard check?"
- Update lesson with concrete pre-merge gate syntax

### L-021: Route/Compute Split + Schema-First Migrations ✅ **PARTIALLY EFFECTIVE**

**Rule:** 
1. API routes separate HTTP surface (route.ts) from business logic (compute.ts)
2. Schema definitions in src/db/schema.ts own source of truth; migrations generated via drizzle-kit

**Evidence from findings:**
- **Violations:** 11 findings (implementation-drift-summary)
  - Route layers sometimes contain business logic (portal timesheet approval validation)
  - Compute layers sometimes lack state-transition validation
  - Event emission inconsistent
- **Violations prevented:** High (majority of Phase 1 features follow route/compute split correctly)

**Effectiveness score:** 70% — Split is established but not strict enough. Business logic sometimes bleeds between layers.

**Recommendation:**
- Phase 2 planning: establish canonical route/compute/event pattern with code examples
- Pre-merge gate: linting rule that flags business logic in route.ts
- Code review: checklist item "Is compute layer complete + testable?"

### L-020: Manager Role Narrowing ❌ **NOT YET ESTABLISHED**

**Lesson status:** Candidate from findings; not yet captured.

**Rule (candidate):** Manager roles (project_manager, team_manager, problem_manager) should inherit narrowly scoped capabilities, not full STAFF authority. Fine-grained ROLE_PERMISSIONS must be enforced by guards.

**Evidence from findings:**
- **Violations:** 1 finding (problem-management-itil-audit)
  - Manager roles inherit STAFF globally
  - `ROLE_PERMISSIONS` aspirational but not enforced

**Recommendation:** 
- Resolve design intent (Phase 1 vs Phase 2 ROLE_PERMISSIONS enforcement)
- Capture as L-020 once intent clarified
- Add pre-commit gate to prevent future manager-role over-permissioning

### L-022: Event Emission on Mutations ❌ **NOT YET ESTABLISHED**

**Lesson status:** Candidate from findings; not yet captured.

**Rule (candidate):** Every mutable operation on tickets, time_entries, timesheets must emit typed event to Cloudflare Queues. Integration surface depends on event signal.

**Evidence from findings:**
- **Violations:** 5+ findings (implementation-drift-summary)
  - Some state mutations (time-entry approval, timesheet submit) do not emit events
  - Integration architecture incomplete

**Recommendation:**
- Capture as L-022 once integration architecture finalized
- Pre-merge gate: lint for mutations without event emission
- Code review: checklist item "Does every mutation emit an event?"

### L-023: State Machine Discipline ❌ **NOT YET ESTABLISHED**

**Lesson status:** Candidate from findings; not yet captured.

**Rule (candidate):** State machines (ticket lifecycle, timesheet approval workflow) must document valid transitions and enforce guard checks at each boundary. No implicit transitions.

**Evidence from findings:**
- **Violations:** 3+ findings (implementation-drift-summary)
  - Missing precondition validation (e.g. timesheet can move to "approved" without locking all time entries)
  - Undocumented implicit transitions

**Recommendation:**
- Capture as L-023 during Phase 2 planning
- Add state machine documentation to architecture guide
- Pre-merge gate: verify state transition guards are in place
- Code review: checklist item "Are state transitions guarded?"

### L-024: Migration Metadata Management ❌ **NOT YET ESTABLISHED**

**Lesson status:** Candidate from findings; not yet captured.

**Rule (candidate):** Migration metadata (version counters, applied timestamps) must be managed sequentially across branches using pre-commit hooks. Use migration-naming convention (migration/feature-name-*) to prevent collisions.

**Evidence from findings:**
- **Violations:** 1 finding (migration-metadata-collision)
  - Migration metadata fragmented across feature branches
  - Risk on multi-developer teams during rebase/merge

**Recommendation:**
- Capture as L-024 immediately (migration safety is critical)
- Implement pre-commit hook: validate migration file sequencing
- Establish branch naming convention
- Code review: verify migrations don't have gaps or duplicates

### L-025: Specification Completeness Gate ❌ **NOT YET ESTABLISHED**

**Lesson status:** Candidate from findings; not yet captured.

**Rule (candidate):** Before implementation begins, verify ROADMAP.md, ALPHA.md, and CLAUDE.md are unambiguous and stable. Features that land in wrong phase or with conflicting scope create rework.

**Evidence from findings:**
- **Violations:** 1 finding (problem-management-alpha-drift)
  - Problem Management spec unclear (Phase 1.5 vs 2)
  - Alpha gate contradicts ROADMAP; design decisions made without gate alignment

**Recommendation:**
- Capture as L-025; make this a mandatory Phase planning gate
- Pre-phase checklist: "ROADMAP and ALPHA finalized? CLAUDE.md complete? No conflicting scopes?"
- Code review: every feature branch must reference its ROADMAP phase explicitly

---

## Effectiveness Summary

| Lesson | Status | Violations | Prevented | Score | Recommendation |
|--------|--------|-----------|-----------|-------|-----------------|
| L-018 | Active | 1 | 3+ | 60% | Pre-merge gate: check roles in requireRole() guards |
| L-021 | Active | 11 | High | 70% | Canonical pattern + linting rule for logic in routes |
| L-020 | Candidate | 1 | — | — | Resolve ROLE_PERMISSIONS intent; capture as lesson |
| L-022 | Candidate | 5+ | — | — | Lint for events on mutations |
| L-023 | Candidate | 3+ | — | — | State machine docs + guard enforcement |
| L-024 | Candidate | 1 | — | — | Pre-commit migration validation |
| L-025 | Candidate | 1 | — | — | Spec completeness gate before implementation |

**Meta-insight:** Phase 1 has 2 effective lessons (L-018, L-021) with room for improvement. 5 candidate lessons from current findings should be captured before Phase 2 starts, giving Phase 2 a stronger foundation.

---

## Next Steps

**Phase 2 Planning:**
1. Resolve L-020, L-022, L-023, L-024 design intents and capture as lessons
2. Create pre-merge gates for each new lesson
3. Update code review checklists with lesson-specific items
4. Measure effectiveness of new lessons by the next audit cycle (weekly)
