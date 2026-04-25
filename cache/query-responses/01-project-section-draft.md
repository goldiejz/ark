---
query: "How to draft the Project section of CLAUDE.md for a [project-type]?"
optimized_prompt: |
  Draft a Project section for a [project-type] project named "[project-name]".
  
  The Project section should:
  1. Name the project and its operational role in one sentence
  2. State the destination aspiration (be honest about current stage)
  3. Mention relationship to sibling systems if applicable (for Strategix: mention if this is IOC/RevOps/ServiceDesk half)
  
  Use this template:
  ```
  [Project Name] — [operational role].
  [Current stage description]; [destination aspiration].
  [Relationship to sibling systems if multi-project programme].
  ```
  
  Reference the bootstrap template for [project-type]:
  - service-desk: timesheet + multi-tenant ticketing platform, sibling to RevOps/IOC
  - revops: commercial operations (quotes, pipeline, margin, commission, billing), sibling to IOC
  - ops-intelligence: signal correlation + operator decision support, sibling to RevOps
  
  Do NOT use AIOps language in Phase 1. Do NOT claim "production-ready" when pitch-ready. Be honest about current stage.
tier_recommendation: Haiku
cost_estimate: "~800 tokens"
last_updated: "2026-04-25"
cache_hit_rate: "5+ times (service-desk, crm, ioc bootstraps + customer A prep)"
depends_on: ["bootstrap/project-types"]
---

## Cached Example Responses

### Service Desk Project
```
Strategix Service Desk — the group-wide service desk + timesheet platform.
Third platform in the Strategix internal platform programme alongside 
`strategix-revops` (commercial half) and `strategix-ioc` (operational half).
```

### RevOps Project
```
Strategix RevOps Platform — the commercial half of the Strategix 
internal platform programme. Sibling system is `strategix-ioc` (operational half).
```

### Ops Intelligence Project
```
Strategix IOC (Intelligence Operations Center) — the operational half 
of the Strategix internal platform programme. Sibling system is `strategix-revops` 
(commercial half).
```

## When to Use This Cache
- Bootstrap step 2 (draft Project section)
- User asks: "How should I describe this project?"
- CLAUDE.md project section needs drafting
- Check similar project type in cache first

## If Cache Misses (update procedure)
1. Run full prompt with Sonnet
2. Compare result to cached example for same project-type
3. If new pattern discovered: update cache, log change, note why
4. If similar to cached version: cache was good, reuse

## Common Variations
- **Single-tenant vs multi-tenant:** RevOps emphasizes "single-tenant, internal"; ServiceDesk emphasizes "multi-tenant from day zero"
- **Aspiration vs current:** OpsInt warns against "AIOps" in Phase 1; ServiceDesk honest about "pitch-ready, not operationally-ready"
- **Sibling relationships:** Only mention for multi-project programmes (Strategix has 3); single-project customers don't reference siblings

## Anti-Patterns to Avoid
- ❌ "Replacement for [external tool]" (set expectations wrong)
- ❌ "Production-ready" when still in Phase 1 (be honest)
- ❌ Vague aspiration ("world-class", "best-in-class") — be specific
- ❌ No current-stage description — always state where you are now
