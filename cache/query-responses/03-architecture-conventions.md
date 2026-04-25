---
query: "What are the critical architecture conventions for a [project-type]?"
optimized_prompt: |
  List critical architecture conventions for a [project-type] project.
  
  For ALL project-types (universal):
  1. RBAC centralized (all roles in one file, no inline role arrays in routes)
  2. Route/compute split (HTTP surface separate from business logic)
  3. Schema-first (schema definitions own source of truth; migrations generated)
  4. Currency suffix on financial columns (_zar, _usd)
  5. Audit columns or audit logs on mutations
  6. Event emission on state changes (for integration surface)
  7. Zod validation at system boundaries
  8. Soft-delete on mutable tables (no hard deletes)
  
  For [project-type] specifically, add:
  - service-desk: tenant on every table, feature-folder organization (src/features/<feature>/)
  - revops: field-level shaping (hide cost/margin from sales role), range validation both layers
  - ops-intelligence: connector pattern (non-CF-proxied URL + Host header), separate cron-worker deployment
  
  Format:
  ```
  - **Convention Name.** Brief description + rationale.
  - **Convention 2.** ...
  ```
tier_recommendation: Haiku
cost_estimate: "~1000 tokens"
last_updated: "2026-04-25"
cache_hit_rate: "8+ times (any project starting with shared stack)"
depends_on: ["bootstrap/project-types"]
---

## Cached Example Responses

### Service Desk Conventions
```
- **Tenant on every table.** Every query is tenant-scoped via middleware.
- **RBAC centralised.** All roles in `src/lib/rbac.ts`. Route guards via `requireRole()`.
- **Route/compute split.** HTTP surface in `route.ts`; logic in `compute.ts`.
- **Schema-first migrations.** Drizzle definitions own source of truth.
- **Currency suffix.** All financial columns end `_zar` or `_usd`.
- **Audit columns on mutations.** `created_at`, `created_by`, `updated_at`, `updated_by`.
- **Event emission on mutations.** Every ticket/time/timesheet change emits event.
- **Feature-folder org.** `src/features/<feature>/` contains routes, compute, UI.
- **Zod at boundaries.** All inbound payloads validated; outbound events typed.
- **Soft-delete.** No hard deletes on `tickets`, `time_entries`, `timesheets`.
```

### RevOps Conventions
```
- **Schema-first.** `d1/schema.sql` is canonical. Every change ships as numbered migration.
- **Currency suffix.** All financial columns end in `_[currency]`.
- **UUID + AUTOINCREMENT.** UUIDs for domain rows; AUTOINCREMENT for logs.
- **RBAC in middleware.** `requireRole()` from `functions/api/middleware/rbac.ts`.
- **Field-level shaping.** `shapeQuoteForRole()` strips cost/margin fields.
- **Range validation at both layers.** Handler validation + schema CHECK constraint.
- **Audit every mutation.** Sensitive routes write to `audit_log`.
```

### Ops Intelligence Conventions
```
- **Compute/route split.** API routes separate `route.ts` (HTTP surface) from `compute.ts` (logic).
- **RBAC.** All role constants in `src/lib/auth-guards.ts`. Never define local role arrays.
- **Event emission.** Connectors emit `ConnectorEvent` to `onEventsReceived()` in event-pipeline.ts.
- **Connector pattern.** Fetch via non-CF-proxied URL; override `Host` to tenant URL.
- **Cron worker.** Separate deployment in `cron-worker/`. Deploy with `cd cron-worker && npx wrangler deploy`.
- **Drizzle.** Owns schema + queries. `drizzle-kit` for migrations.
- **No lint blocking.** Lint is advisory; typecheck + test + build are gate.
```

## Why These Conventions

Each convention exists because teams discovered a failure mode:
- **RBAC centralized**: Hidden permission escalation when roles spread across 20 route files
- **Route/compute split**: Business logic in routes is hard to test; compute layer is testable
- **Audit columns**: Can't debug "who changed this and when?" without them
- **Soft-delete**: Hard deletes lose audit trail; soft-delete preserves it
- **Tenant on every table**: Multi-tenant SQL injection risk when tenant_id forgotten
- **Currency suffix**: Financial logic errors when mixing ZAR and USD without explicit column names
- **Zod at boundaries**: Type safety at runtime; catches API contract violations

## When to Use This Cache
- Bootstrap step 5 (architecture conventions section)
- Architecture review (check: are we following convention X?)
- Code review (spot: this route has business logic, should be in compute)
- Onboarding (new team member learns conventions)

## If Cache Misses (update procedure)
1. Run full prompt with Sonnet (reads project-type template + actual codebase if available)
2. Compare result to cached example for same project-type
3. If new convention discovered: update cache, add rationale (what failure mode does it prevent?)
4. If similar: cache was good, reuse

## Common Misses
- Project adds a convention without rationale (makes it feel like dogma, not practice)
- Convention varies across 2 repos of same type (convention is not sticky)
- Convention exists in docs but violated in code (drift between theory and practice)
