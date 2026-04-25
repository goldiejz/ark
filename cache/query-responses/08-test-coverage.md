---
query: "What test coverage targets should a [project-type] have?"
optimized_prompt: |
  Define test coverage targets for a [project-type] project.
  
  Coverage minimum: 80% across all test types (unit, integration, E2E).
  
  For [project-type], critical paths requiring 90%+ coverage:
  - service-desk: time capture (timer, manual, activity dwell), timesheet approval, tenant isolation
  - revops: quote creation, margin approval, commission calculation, field-level shaping
  - ops-intelligence: signal ingestion, correlation logic, advisory evaluation, event emission
  
  Test strategy:
  1. Unit tests: Individual functions, utilities, components (60-70% of coverage)
  2. Integration tests: API endpoints, database operations, auth gates (20-30%)
  3. E2E tests: Critical user journeys (5-10%)
  
  Output:
  ```
  - **Unit tests**: 80%+ coverage on [critical module]
  - **Integration tests**: Every API route tested with auth + tenant scope
  - **E2E tests**: Core workflows (ticket creation → approval, quote → export, etc.)
  - **Gate**: All tests must pass in CI before merge
  ```
tier_recommendation: Haiku
cost_estimate: "~900 tokens"
last_updated: "2026-04-25"
cache_hit_rate: "6+ times (every project needs testing strategy)"
depends_on: ["bootstrap/project-types"]
---

## Cached Example: Service Desk Test Coverage

```
- **Unit tests (60%)**: 
  - Time entry validation (timer start, dwell calculation, manual entry parsing)
  - Timesheet state machine (draft → submitted → approved → signed)
  - Tenant scoping (queries filtered by tenant_id)
  - Role-based access (requireRole() guards)
  
- **Integration tests (30%)**:
  - POST /tickets (create incident, tenant-scoped)
  - POST /time-entries (start timer, submit manual, calculate dwell)
  - POST /timesheets/submit (validate all time entries locked, emit event)
  - POST /timesheets/approve (manager role only, audit trail)
  - GET /timesheets/:id (customer can only see own, auth guard)
  
- **E2E tests (10%)**:
  - Core: Engineer creates time entry → submits timesheet → Manager approves → Customer signs
  - Portal: Customer views ticket status → leaves comment → sees approval progress
  
- **Coverage target**: 80%+ overall, 90%+ on time capture + approval paths
```

### Critical Paths Requiring 90%+ Coverage

| Path | Why | Test Cases |
|------|-----|-----------|
| Time capture logic | Core value; billing accuracy depends on it | Timer start, dwell, manual entry, rounding |
| Timesheet approval | Audit trail; financial controls | Draft → Submit → Approve → Sign state transitions |
| Tenant isolation | Security; multi-tenant enforcement | Query filtering, auth gates, cross-tenant attempts |
| Role gates | RBAC correctness; permission escalation risk | Engineer/Manager/Admin/Customer role guards |

## Cached Example: RevOps Test Coverage

```
- **Unit tests (65%)**:
  - Quote template validation (rate card application, discount curves)
  - Margin calculation (cost + margin = price)
  - Commission formula (base rate, bonus tiers, clawback logic)
  - Field-level shaping (hide cost/margin from sales role)
  
- **Integration tests (25%)**:
  - POST /quotes (create, apply rate card, calculate margin, audit log)
  - POST /quotes/:id/approve (margin gate, role-based approval)
  - GET /quotes/:id (customer sees differently from sales sees)
  - GET /commissions (calculation + backtest)
  
- **E2E tests (10%)**:
  - Core: Sales creates quote → Finance approves margin → Export for billing
  
- **Coverage target**: 80%+ overall, 95%+ on margin approval + commission calculation
```

## Cached Example: Ops Intelligence Test Coverage

```
- **Unit tests (60%)**:
  - Signal ingestion (HaloPSA connector, N-central connector)
  - Correlation logic (merge duplicate signals, prioritize by severity)
  - Advisory evaluation (rule matching, confidence scoring)
  - Rule state machine (enabled → disabled → archived)
  
- **Integration tests (30%)**:
  - POST /events (ingest from connector, emit internal event)
  - POST /rules/toggle (enable/disable, audit trail)
  - POST /advisories/:id/ack (operator ack, clear from dashboard)
  - GET /events (operator-scoped view)
  
- **E2E tests (10%)**:
  - Core: HaloPSA incident ingested → correlated with N-central alert → advisory generated 
    → operator ack/dismiss
  
- **Coverage target**: 80%+ overall, 90%+ on signal correlation + advisory evaluation
```

## Test Infrastructure

```
# Vitest configuration (all projects)
export default defineConfig({
  test: {
    globals: true,
    environment: "node",
    coverage: {
      provider: "v8",
      reporter: ["text", "json", "html"],
      lines: 80,
      branches: 80,
      functions: 80,
      statements: 80,
      exclude: ["node_modules", ".venv", "build", "dist"],
    },
  },
});
```

## CI Gate

```yaml
# .github/workflows/test.yml
- name: Test Coverage
  run: npm run test:coverage
  
- name: Check Coverage Threshold
  run: |
    if npm run test:coverage | grep -E "lines\s*[0-7][0-9]\.[0-9]+%"; then
      echo "Coverage below 80%"
      exit 1
    fi
```

## Common Anti-Patterns

- ❌ **Test-first, verify-last**: Write tests that pass without checking coverage
- ❌ **Mocking all dependencies**: Hard to detect real integration bugs
- ❌ **No E2E tests**: Unit + integration pass, but user workflow fails
- ❌ **Coverage game**: Add meaningless assertions to hit 80% target
- ❌ **Separate test DB**: Local tests pass, prod tests fail (use same DB schema)

## When to Use This Cache
- Bootstrap step 9 (test infrastructure + coverage targets)
- Code review (missing test for critical path?)
- CI configuration (what threshold to enforce?)
