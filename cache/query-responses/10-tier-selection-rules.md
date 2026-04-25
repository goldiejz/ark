---
query: "When should I use Haiku vs Sonnet vs Opus for a task?"
optimized_prompt: |
  Determine which Claude model tier to use for a given task.
  
  **Haiku 4.5** (90% of Sonnet capability, 3x cost savings):
  - Lightweight agents with frequent invocation
  - Pair programming and code generation (simple fixes)
  - Worker agents in multi-agent systems (running in parallel)
  - Parsing and classification tasks
  - Cached responses (answering from brain cache is cheap)
  
  **Sonnet 4.6** (Best coding model, balanced cost):
  - Main development work
  - Orchestrating multi-agent workflows
  - Complex coding tasks (multi-file refactoring)
  - Architecture decisions with tradeoff analysis
  - Debugging non-trivial issues
  
  **Opus 4.7** (Deepest reasoning, 2x Sonnet cost):
  - Complex architectural decisions
  - Maximum reasoning requirements
  - Research and analysis tasks (novel territory)
  - System-wide refactoring with cross-cutting impacts
  - Strategic planning (roadmap, phasing, scoping)
  
  Decision tree:
  ```
  Q: Is this cached in brain?           → Haiku (cached response)
  Q: Is this code-generation only?      → Haiku (simple generation)
  Q: Is this main dev work?             → Sonnet (default)
  Q: Is this architectural?             → Sonnet (unless novel)
  Q: Is this entirely novel/risky?      → Opus (maximum reasoning)
  Q: Is this tradeoff analysis?         → Sonnet (strong at this)
  Q: Is this debugging?                 → Sonnet (good at this)
  Q: Is this multi-agent coordination?  → Sonnet (orchestrator) + Haiku (workers)
  ```
tier_recommendation: Haiku
cost_estimate: "~500 tokens (this decision itself)"
last_updated: "2026-04-25"
cache_hit_rate: "10+ times (resolve-tier.mjs queries this constantly)"
depends_on: ["performance.md"]
---

## Decision Matrix

| Task Type | Haiku | Sonnet | Opus | Rationale |
|-----------|-------|--------|------|-----------|
| Code generation (template, small feature) | ✅ | — | — | 90% capable, much cheaper |
| Multi-file refactoring | — | ✅ | ⚠️ | Sonnet handles well; Opus only if major risk |
| Architecture decision | — | ✅ | ✅ | Sonnet good; Opus for novel decisions |
| Debugging non-trivial bug | — | ✅ | — | Sonnet good at this; rarely need Opus |
| Parsing/classification | ✅ | — | — | Haiku sufficient |
| API response caching | ✅ | — | — | Cached response cheap to retrieve |
| Novel problem solving | — | ⚠️ | ✅ | Opus for maximum reasoning |
| Tradeoff analysis | — | ✅ | — | Sonnet good; Opus overkill |
| Test generation | ✅ | ✅ | — | Haiku for simple, Sonnet for complex |
| Prompt refinement | ✅ | — | — | Haiku can refine existing prompts |

## Real Examples

### ✅ Use Haiku
```
Task: "Rename variable X to Y across the codebase"
⟹ Haiku: Simple find/replace, high confidence
Cost: ~1K tokens (1/3 of Sonnet)

Task: "Here's a cached prompt; answer this query using it"
⟹ Haiku: Retrieval + light formatting
Cost: ~500 tokens

Task: "Generate a test case for this function"
⟹ Haiku: Template-based generation
Cost: ~1K tokens
```

### ✅ Use Sonnet
```
Task: "Refactor time-entry validation into compute layer"
⟹ Sonnet: Multi-file change, dependency analysis, testing
Cost: ~5K tokens (baseline for main dev work)

Task: "Should we use D1 or PostgreSQL for multi-tenancy?"
⟹ Sonnet: Tradeoff analysis (cost, complexity, scale)
Cost: ~3K tokens

Task: "Debug why timezone conversion is off by 1 hour"
⟹ Sonnet: Good at debugging; usually sufficient
Cost: ~2K tokens
```

### ✅ Use Opus
```
Task: "Redesign authentication for 3 sub-projects sharing parent automation"
⟹ Opus: Novel cross-system architecture; maximum reasoning needed
Cost: ~10K tokens (but necessary for this type of decision)

Task: "How should multi-project bootstrap work with shared lessons?"
⟹ Opus: Strategic planning, many variables, system-wide impact
Cost: ~8K tokens

Task: "Analyze whether our 7-phase plan is correct; suggest improvements"
⟹ Opus: High-level reasoning + strategic critique
Cost: ~6K tokens
```

## Cost Analysis by Task Type

| Task | Haiku | Sonnet | Opus | $/Task | Saved by Haiku |
|------|-------|--------|------|--------|-----------------|
| Simple code gen | 1K | 3K | 8K | 3:1 vs Sonnet | 66% |
| Multi-file refactor | — | 5K | 10K | 1:1 vs Sonnet | N/A (need Sonnet) |
| Architecture decision | — | 3K | 8K | 2.6:1 vs Sonnet | N/A (need Sonnet+) |
| Cached response | 500 | 1.5K | 4K | 3:1 vs Sonnet | 66% |

## Avoiding Waste

❌ **Using Opus for simple tasks** (code gen, parsing)
- Costs 8x Haiku for 90% same capability

❌ **Using Haiku for novel decisions**
- Haiku may give shallow reasoning; need Opus for risky decisions

❌ **Not using Sonnet as default**
- Haiku good at specific tasks, Opus at specific decisions; Sonnet handles 80% of dev work

❌ **Not caching when you can**
- Cached response (Haiku) is 6x cheaper than asking Sonnet

## When to Escalate

- **Haiku → Sonnet**: Task requires multi-file analysis, architecture reasoning, or debugging non-obvious bugs
- **Sonnet → Opus**: Task is novel (no similar precedent), affects multiple projects, or needs maximum reasoning
- **Always start Haiku**: If it fails or times out, escalate; don't preemptively jump to Sonnet

## Related Observability

- `token-spend-log.md` in brain tracks actual costs vs estimates
- `resolve-tier.mjs` in parent automation makes these decisions
- Cache hit rates determine when Haiku vs Sonnet used

## When to Use This Cache
- resolve-tier.mjs queries this for every task dispatch
- New automation decision: "What model should this use?"
- Cost analysis: "Are we spending on the right tier?"
