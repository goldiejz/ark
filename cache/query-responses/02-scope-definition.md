---
query: "How to define Phase 1 scope for a [project-type]?"
optimized_prompt: |
  Define Phase 1 scope for a [project-type] project named "[project-name]".
  
  Phase 1 scope should:
  1. List 5-8 core features that ship in Phase 1
  2. For service-desk: include ticket types, time capture, portal, multi-tenant
  3. For revops: include quotes, pipeline, pricing, commission, billing
  4. For ops-intelligence: include 2-3 connectors, advisory batch analysis, operator surface
  5. Reference actual feature counts from .planning/STATE.md
  
  Format:
  ```
  Phase 1 ships:
  - Feature 1: description
  - Feature 2: description
  ...
  
  Specific counts live in `.planning/STATE.md` (tables, routes, rules, connectors).
  ```
  
  Then immediately list "Out of Scope" (Phase 2+) to set boundaries:
  - Azure AD / M365 integration (Phase 2)
  - Runtime rule editing (Phase 2)
  - Custom dashboards (Phase 2)
  - etc.
  
  Use bootstrap templates as reference for what ships Phase 1 vs Phase 2+ per project-type.
tier_recommendation: Haiku
cost_estimate: "~1200 tokens"
last_updated: "2026-04-25"
cache_hit_rate: "4+ times (three Strategix projects + customer A prep)"
depends_on: ["bootstrap/project-types", ".planning/STATE.md"]
---

## Cached Example Responses

### Service Desk Phase 1 Scope
```
Phase 1 ships:
- One ticket type: Incident (with status lifecycle + SLA timers)
- Projects as first-class: Client → Project → Ticket
- Structured time capture: timer + manual entry + activity dwell
- Weekly timesheets with customer sign-off
- Role-default dashboards (Engineer, Manager)
- Report export (CSV + PDF)
- Customer portal (self-serve submission + status + approval)
- Multi-tenant isolation (2+ seed tenants)
- Webhook-out admin surface (integration proof)

Specific counts live in `.planning/STATE.md`:
- Tables: 8 (tickets, time_entries, timesheets, ...)
- Routes: 12 (ticket CRUD, time entry CRUD, ...)
- Tests: 80%+ coverage on time capture path
```

### RevOps Phase 1 Scope
```
Phase 1 ships:
- Standard quote issuance
- Weighted pipeline
- Governed pricing (rate cards + discount curves)
- Platform-routed margin approval
- Commission calculation + backtest
- Account/client 360 view
- Billing/metering integration
- Finance reporting

Specific counts: [from STATE.md]
- Database: D1 SQLite, schema-first migrations
- Auth: Azure AD SSO via Cloudflare Access
- Frontend: React 19 SPA on Cloudflare Pages
```

### Ops Intelligence Phase 1 Scope
```
Phase 1 ships:
- Cross-source event ingestion + live correlation (HaloPSA + N-central)
- Advisory AI batch analysis (nightly Claude run)
- Weekly relevance tuning from operator feedback
- Runtime rule enable/disable + confidence tuning (RBAC-enforced)
- Wall/desktop/mobile consumption surface
- Operator ack/dismiss + audit log

Out of Scope (Phase 2+):
- Autonomous AIOps (no closed-loop write-back)
- Predictive SLA breach detection (no ground-truth reconciliation)
- Runtime editing of rule logic (requires code deploy)
- Client-facing portal or multi-tenant operator separation
```

## Out of Scope Template (Universal)

```
Phase 1 explicitly defers:
- [Feature]. Deferred to [Phase]. [Reason if non-obvious].
- [Feature]. Deferred to [Phase].
...
```

## When to Use This Cache
- Bootstrap step 3 (define current scope + deferrals)
- User asks: "What should Phase 1 include?"
- ROADMAP.md needs scope definition
- Planning Phase 2 boundaries

## If Cache Misses (update procedure)
1. Run full prompt with Sonnet (reads project-type template + STATE.md)
2. Compare result to cached example for same project-type
3. If new feature pattern: update cache, note rationale
4. If similar: cache was good, reuse

## Common Anti-Patterns
- ❌ Phase 1 scope creep (adding "just one more thing" from Phase 2)
- ❌ Vague feature names ("dashboard", "reporting" without specifics)
- ❌ No explicit deferrals (users assume everything ships Phase 1)
- ❌ Confusing "Phase 1 feature list" with "Phase 1 + 2 + 3 feature list"
