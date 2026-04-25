---
query: "How to define completion language (gates) for a [project-type]?"
optimized_prompt: |
  Define completion language (gate definitions) for a [project-type] project.
  
  Completion language is HONEST NAMING for what stage you're at. Don't call Phase 1 
  "production-ready" when it's "pitch-ready". Each project-type has different gates.
  
  For [project-type], use:
  - service-desk: code-landed, staging-deployed, pitch-verified (NOT "production-ready" in Phase 1)
  - revops: code-closed, alpha-testable, alpha-proven (NOT "live" until Alpha group runs real workflow)
  - ops-intelligence: technical foundation, workflow adoption, operational improvement, destination-stage aspiration
  
  For each gate, define:
  1. What MUST be true to pass (tests, demos, metrics)
  2. What is NOT required (e.g., production monitoring, compliance audit)
  3. Who decides (product lead, ops team, finance)
  
  Output:
  ```
  - **[Gate name]**: [Definition]. [What must pass]. [Not required].
  ```
tier_recommendation: Haiku
cost_estimate: "~800 tokens"
last_updated: "2026-04-25"
cache_hit_rate: "5+ times (every project needs honest stage naming)"
depends_on: ["bootstrap/project-types"]
---

## Cached Example: Service Desk Gates

```
- **code-landed**: Implementation + tests pass. Merged to main. Not required: E2E demo, staging deploy.
- **staging-deployed**: Running on staging Worker with seed data. Portal works, staff app works. 
  Not required: Production monitoring, 99.9% uptime SLA.
- **pitch-verified**: Demo executes end-to-end without errors. Core workflows (create ticket → approve timesheet) work. 
  Not required: Performance optimization, production operational posture, compliance audit.
```

### What Does NOT Pass the Gates in Phase 1
- ❌ "Production-ready" (reserve for Phase 2 operational posture)
- ❌ "Compliance signed off" (legal review deferred)
- ❌ "99.9% uptime" (SLA enforcement Phase 2)
- ❌ "Scaled to 1M tickets" (performance optimization Phase 2)

## Cached Example: RevOps Gates

```
- **code-closed**: Implementation + tests pass. Lint clean. Build succeeds.
- **alpha-testable**: Exposed to Alpha user group (Finance + Sales leads). Running on staging D1 with real rate card data.
  Not required: Production database, real quotes
- **alpha-proven**: Alpha user group runs real workflow (create quote → approve margin → export) 
  without fallback to Excel. No side-channel use of spreadsheets for 1 week.
  Not required: All 20 features complete; shedding legacy systems, compliance sign-off.
```

### Common Mistake: Calling "code-closed" Done
❌ "The code is done" (it's code-closed, not alpha-proven; Excel still in use)
✅ "Code-closed: tests pass, ready for Alpha testing"

## Cached Example: Ops Intelligence Gates

```
- **technical foundation**: Code lands, tests pass, runs in production.
  - Endpoint wired: GET /events, POST /rules, POST /ack
  - Tests: 80%+ coverage on signal path
  - Deploy: Runs on production Worker without errors
  - Not required: Operator daily use, SLA metrics
  
- **workflow adoption**: Operators use it as primary surface (not fallback).
  - Daily active users: 80%+ of ops team
  - Usage metric: >50% of incidents get ack/dismiss via platform (vs Slack)
  - Not required: All connectors wired, rule confidence perfect
  
- **operational improvement**: Pre/post metrics show real change on target incident classes.
  - Pre: MTTR = 45min, detection gap = 2-3 min
  - Post: MTTR = 20min, detection gap = 30s
  - Cost: measurable efficiency gain (fewer SLA breaches, faster remediation)
  - Not required: "AIOps" or closed-loop autonomy; we're advisory-only
  
- **destination-stage aspiration**: Avoid this in Phase 1. Reserve for future when truly autonomous.
```

### Honest Positioning Rules
- ✅ "Advisory analysis" (current: manual operator review of AI suggestions)
- ✅ "Operator decision support" (we recommend; operator decides)
- ❌ "AIOps" (reserved for closed-loop autonomy; not there in Phase 1)
- ❌ "99.9% detection accuracy" (imprecise; mixes prediction + action success)

## When to Use This Cache
- Bootstrap step 7 (ALPHA.md gate definition)
- Planning Phase 2 (when does Phase 1 gate become Phase 2 entry gate?)
- Code review (is this feature code-landed? staging-deployed? pitch-verified?)
- Stakeholder communication ("We're code-closed but not alpha-proven yet")

## Common Anti-Patterns

- ❌ **Aspirational gates**: "We'll be production-ready when tests pass" (tests passing = code-landed, not production-ready)
- ❌ **Gate inflation**: Calling Phase 1 feature "shipped" when only dev saw it
- ❌ **No rollback plan**: What happens when Alpha testing fails? How do we go back?
- ❌ **Moving goalposts**: Gate definition changes mid-phase because pressure to ship
- ❌ **AIOps language in Phase 1**: Calling it "autonomous" when it's advisory-only

## Related Documents
- **ALPHA.md** in repo (.planning/) — captures gate definitions + success criteria
- **STATE.md** in repo (.planning/) — tracks which features are at which gate
