---
vault_section: findings/by-customer/strategix
last_updated: 2026-04-25
total_findings: 16
total_scopes: 4
---

# Strategix Service Desk — Findings Index

**Period:** 2026-04-24 to 2026-04-25 (Phase 1 through Phase 2 planning)
**Source:** strategix-servicedesk tasks/gemini-audits/findings/
**Ingestion method:** Parallel audit review (Codex + design-watchdog fallback)
**Coverage:** 16 audit findings classified by scope + severity

---

## By Scope

### Schema Drift (3 findings)

Schema-level issues: missing soft-delete affordances, nullability ambiguities, fragmented migrations.

| Finding | Audit | Verdict | Severity | Status |
|---------|-------|---------|----------|--------|
| **strategix-schema-001** | phase2-schema-audit | PARTIAL | MEDIUM | Unresolved: add `deleted_at` to work_packages before compute layer |
| **strategix-schema-002** | pm-problem-schema-audit | PARTIAL | MEDIUM | Unresolved: RBAC inheritance scope + priority nullability; user decision required |
| **strategix-schema-003** | migration-metadata-collision | PARTIAL | HIGH | Mitigated: manual coordination; medium-term: validation hook + naming convention |

**Cross-repo risk:** All three Strategix projects use D1 + Drizzle. Migration fragmentation and missing soft-delete patterns are universal risks as projects scale.

**Prevention lesson:** L-021 (schema discipline) + new L-024 (migration metadata management).

---

### RBAC Lockout (1 finding)

RBAC permission scope drift: fine-grained permissions not enforced by route guards.

| Finding | Audit | Verdict | Severity | Status |
|---------|-------|---------|----------|--------|
| **strategix-rbac-001** | problem-management-itil-audit | PARTIAL | MEDIUM | Unresolved: clarify ROLE_PERMISSIONS enforcement scope (Phase 1 vs Phase 2) |

**Pattern:** Manager roles inherit STAFF globally; `ROLE_PERMISSIONS` (fine-grained caps) defined but never checked. Result: manager can do unintended operations (ticket creation, timesheet submit).

**Cost:** Hidden permission escalation; audit trail shows STAFF operations that should be domain-scoped.

**Governing lesson:** L-018 (RBAC enum completeness) + L-020 (manager role narrowing).

---

### Contradiction / Gate Drift (1 finding)

Specification contradictions: features implemented in wrong phase; scope ambiguity between ROADMAP and implementation.

| Finding | Audit | Verdict | Severity | Status |
|---------|-------|---------|----------|--------|
| **strategix-contradiction-001** | problem-management-alpha-drift | PARTIAL | MEDIUM | Unresolved: clarify Problem Management phase (1.5 vs 2); align ROADMAP if needed |

**Pattern:** Problem Management (ITIL type beyond Incident) is Phase 2 per ROADMAP.md but landing in Phase 1 feature branches. Design decisions are being reviewed against Alpha gate, creating false expectations.

**Cost:** Alpha gate becomes ambiguous; Phase 2 planning confused; rework when gate clarified.

**Governing lesson:** L-005 (gate definition before implementation) + L-006 (contradiction pass before merge).

---

### Implementation Drift (11 findings)

Compute-layer design inconsistencies: route/compute split discipline, event emission gaps, state transition validation, error handling.

**Findings:**
- dry-run-audit
- portal-timesheet-approval-implementation
- portal-timesheet-approval-audit
- pass1f-merge-audit
- day-c-report-audit
- timesheet-report-audit
- day-c-implementation-audit
- day-c-phase2-sync-audit
- problem-management-implementation-audit
- problem-management-refactor-audit
- problem-management-deep-audit

See **implementation-drift-summary.md** for recurring patterns and cross-repo relevance.

**Verdict:** MIXED (some findings AGREE with conventions; others NEEDS-CLARIFICATION)
**Severity:** MEDIUM (systemic, not critical)
**Status:** Phase 2 planning should synthesize canonical route/compute/event pattern from these 11 findings.

---

## By Severity

| Severity | Count | Issues |
|----------|-------|--------|
| MEDIUM | 15 | Schema design, RBAC scope, gate drift, compute discipline |
| HIGH | 1 | Migration metadata fragmentation (multi-dev risk) |

---

## By Verdict

| Verdict | Count | Interpretation |
|---------|-------|-----------------|
| PARTIAL | 4 | Design findings identified; some unresolved, some NEEDS-CLARIFICATION |
| MIXED | 11 | Implementation findings vary in verdict; patterns consistent |
| BLOCKS_MERGE | 0 | No findings block Phase 1 merge; all are design/discipline items for Phase 2 |

---

## Synthesis: Meta-Patterns

### Pattern 1: Deferred Design Decisions

**Issue:** Several findings are NEEDS-CLARIFICATION on intent (RBAC enforcement scope, priority nullability, phase scope). These indicate design decisions that must be made before compute layer can be completed.

**Cost:** If deferred to implementation time, brief scope becomes unstable; rework risk increases.

**Prevention:** Phase 2 planning must include a "design intent workshop" that resolves all open NEEDS-CLARIFICATION items before briefs are dispatched.

### Pattern 2: Consistency Over Correctness

**Issue:** Implementation-drift findings reveal inconsistency (some routes validate at boundary, some don't; some emit events, some don't; error handling varies). Individual pieces may be correct, but pattern is incoherent.

**Cost:** Copy-paste errors by new developers; higher bug rate; harder testing.

**Prevention:** Canonical architecture docs + code review checklist + pre-merge gate that flags inconsistency.

### Pattern 3: Specification Gaps

**Issue:** Schema drift, gate drift, and RBAC findings all trace back to incomplete specification (ALPHA.md, ROADMAP.md, CLAUDE.md). Features are implemented with some assumptions; audits expose gaps.

**Cost:** Rework; friction between implementation and review; trust loss ("what's the real spec?").

**Prevention:** Spec completeness gate: before implementation, verify ROADMAP/ALPHA/CLAUDE are unambiguous and stable.

---

## Lesson Candidates

From these 16 findings, the following lessons are captured or should be created:

| ID | Rule | Source Finding | Status |
|----|------|----------------|--------|
| L-018 | RBAC enum completeness | strategix-rbac-001, pm-problem-schema-audit | Existing (cited) |
| L-020 | Manager roles should not inherit full STAFF authority | strategix-rbac-001 | **Candidate** |
| L-021 | Route/compute split discipline + schema-first migrations | phase2-schema-audit, implementation-drift-summary | Existing (cited) |
| L-022 | Event emission on mutations is non-negotiable | implementation-drift-summary | **Candidate** |
| L-023 | State machine discipline: document valid transitions, enforce guards | implementation-drift-summary | **Candidate** |
| L-024 | Migration metadata management: sequential numbering + pre-commit validation | migration-metadata-collision | **Candidate** |
| L-025 | Specification completeness gate before implementation | problem-management-alpha-drift | **Candidate** |

---

## Next Actions

**Phase 2 Planning:**

1. **Resolve outstanding NEEDS-CLARIFICATION items** (RBAC scope, priority nullability, Problem phase)
2. **Synthesize canonical route/compute/event pattern** from implementation-drift findings
3. **Create specification completeness gate** to prevent future drift
4. **Capture lesson candidates** (L-020, L-022, L-023, L-024, L-025) into tasks/lessons.md
5. **Code review checklist** based on 4 recurring implementation patterns

**Timing:** All resolution should happen in Phase 2 planning week before briefs are dispatched to implementation agents.

---

## Findings File Structure

```
findings/by-customer/strategix/
├── INDEX.md (this file)
├── phase2-schema-audit.md
├── pm-problem-schema-audit.md
├── migration-metadata-collision.md
├── problem-management-itil-audit.md
├── problem-management-alpha-drift.md
└── implementation-drift-summary.md
```

Each file contains:
- `finding_id`: unique identifier (strategix-scope-NNN)
- `source`, `audit_id`, `audit_date`: traceability
- `scope`, `verdict`, `severity`, `blocks_merge`: classification
- Summary, key finding(s), recommendation(s)
- Related lessons (cross-link to L-NNN)
- Cross-repo relevance
- Cost analysis + prevention strategies
