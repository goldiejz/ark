---
query: "What are the critical anti-patterns to avoid for a [project-type]?"
optimized_prompt: |
  List critical anti-patterns (things to avoid) for a [project-type] project.
  
  Anti-patterns are lessons learned from failures. Each one cost a team real time/money.
  They're extracted from project review findings and lessons (L-NNN entries).
  
  For ALL project-types (universal):
  1. Claiming "done" when only implementation exists (code-landed ≠ shipped)
  2. Inline role arrays in routes (violates RBAC centralization, causes permission escalation)
  3. No audit trail on mutations (can't debug "who changed this")
  4. Hard deletes (lose audit trail forever)
  5. Trusting user input as truth (always validate at boundaries)
  6. Moving mutable status into doctrine files (drift between docs and code)
  7. Editing prod database directly (bypasses migrations, loses history)
  
  For [project-type] specifically:
  - service-desk: claiming "production-ready" when pitch-ready, trusting body-supplied tenant_id, inline role arrays, signature artifacts deletable
  - revops: calling code-closed "done", "Excel is gone" before Alpha proof, direct D1 edits, implicit column lists in migrations
  - ops-intelligence: using "AIOps" language in Phase 1, claiming "99.9% accuracy", expanding connectors before improving signal quality
tier_recommendation: Haiku
cost_estimate: "~800 tokens"
last_updated: "2026-04-25"
cache_hit_rate: "3+ times (when planning anti-patterns, during code review)"
depends_on: ["bootstrap/project-types", "lessons"]
---

## Cached Example: Service Desk Anti-Patterns

```
1. **Claiming "production-ready" when pitch-ready**
   ⟹ Cost: Stakeholders expect 99.9% uptime; ops team not prepared for real failures
   ⟹ Fix: Use honest gate language: code-landed → staging-deployed → pitch-verified
   
2. **Trusting body-supplied tenant_id**
   ⟹ Cost: Customer A's request hijacked to Customer B's database (data breach)
   ⟹ Fix: Always use authenticated session.tenant_id; never trust request body
   
3. **Inline role arrays in routes**
   ⟹ Cost: Permission check scattered across 20 route files; escalation hidden in one file
   ⟹ Fix: Centralize RBAC in src/lib/rbac.ts; use requireRole() from everywhere
   
4. **Signature artifacts being deletable (soft-delete missing)**
   ⟹ Cost: Customer signs timesheet, then signature disappears on soft-delete
   ⟹ Fix: Signature audit-only, never soft-deleted; audit_log immutable
   
5. **Bundling unrelated cleanup into feature changes**
   ⟹ Cost: Feature + refactor = 2x review effort, harder to bisect bugs
   ⟹ Fix: Feature PR is focused; cleanup is separate PR
```

## Cached Example: RevOps Anti-Patterns

```
1. **Calling "code-closed" done**
   ⟹ Cost: Code passes tests, but Alpha team can't actually generate a quote
   ⟹ Fix: Distinguish code-closed (tests pass) from alpha-testable (works in staging) from alpha-proven (real workflow)
   
2. **"Excel is gone" before Alpha runs without spreadsheet**
   ⟹ Cost: Alpha team still uses Excel side-channel; hidden decisions not in platform
   ⟹ Fix: alpha-proven gate requires: no Excel use for 1 week, all decisions in platform
   
3. **Editing prod D1 directly**
   ⟹ Cost: Schema change lost on redeploy; no migration history; team can't reproduce
   ⟹ Fix: All schema changes via numbered migrations in d1/migrations/; never direct edits
   
4. **Implicit column lists in table-recreate migrations**
   ⟹ Cost: Migration silently drops a column that was never in the explicit list
   ⟹ Fix: Always list columns explicitly: INSERT INTO __new (col1, col2, ...) SELECT col1, col2, ... FROM old
   
5. **Hardcoding business policy**
   ⟹ Cost: "Manager can approve up to $50K" hardcoded in route; policy changes require code deploy
   ⟹ Fix: Use DB-backed rule path; policy is data, not code
```

## Cached Example: Ops Intelligence Anti-Patterns

```
1. **Using "AIOps" language in Phase 1**
   ⟹ Cost: Stakeholders expect closed-loop autonomy; implementation only advisory
   ⟹ Fix: Use "advisory analysis" (Phase 1) vs "autonomous remediation" (future aspiration)
   
2. **Claiming "99.9% intelligence accuracy"**
   ⟹ Cost: Imprecise (mixes prediction success + action success rates)
   ⟹ Fix: Track separately: detection rate (%) + advisory accuracy (%) + operator action rate (%)
   
3. **Expanding connectors before improving signal quality on live ones**
   ⟹ Cost: 5 connectors with 80% signal quality vs 2 connectors at 95%
   ⟹ Fix: Phase 1: nail 2-3 connectors. Phase 2: expand with proven quality bar.
   
4. **Adding routes without requireRole() and without withAudit()**
   ⟹ Cost: Permission escalation, no audit trail for operator actions
   ⟹ Fix: Every route: requireRole(...), and mutations: withAudit()
   
5. **Defining role arrays inline in routes**
   ⟹ Cost: Permission logic scattered; RBAC enum completeness not checked
   ⟹ Fix: src/lib/auth-guards.ts owns role definitions; routes only call requireRole(ROLES.OPERATOR)
   
6. **Not updating in-app changelog for operator-visible changes**
   ⟹ Cost: Operator doesn't know what changed; support gets confused
   ⟹ Fix: src/lib/changelog.ts updated on every user-visible change
```

## Related Lessons (L-NNN)

- **L-018**: RBAC Enum Completeness (prevents #3 in all project-types)
- **L-019**: Honest Gate Language (prevents #1 in all project-types)
- **L-020**: Manager Role Narrowing (prevents over-permissioning)
- **L-021**: Route/Compute Split (prevents business logic in routes)
- **L-022**: Event Emission on Mutations (prevents missing integration signals)

## When to Use This Cache
- Code review (spot: is this violating a known anti-pattern?)
- Planning Phase 2 (lessons from Phase 1 anti-patterns)
- Onboarding (new team member: "here's what NOT to do")

## How to Add New Anti-Patterns

When you discover a new anti-pattern:
1. Document it: what is the mistake? what's the cost?
2. Capture as lesson (L-NNN) in tasks/lessons.md
3. Update this cache
4. Add to pre-merge checklist or linting rule
