# Query Response Cache Index

Cache stores optimized prompts + cached responses for common bootstrap queries. Enables Haiku to answer from cache (~500 tokens) instead of Sonnet querying from scratch (~3K tokens).

## Cache Entries (10 queries, 100% of bootstrap flow)

### Query Responses (per-question caching)

| Query | Tier | Cost | Cache Hit Rate | Updated |
|-------|------|------|---|---------|
| [01-project-section-draft.md](01-project-section-draft.md) | Haiku | 800 | 5+ | 2026-04-25 |
| [02-scope-definition.md](02-scope-definition.md) | Haiku | 1200 | 4+ | 2026-04-25 |
| [03-architecture-conventions.md](03-architecture-conventions.md) | Haiku | 1000 | 8+ | 2026-04-25 |
| [04-rbac-structure.md](04-rbac-structure.md) | Sonnet | 1500 | 6+ | 2026-04-25 |
| [05-constraints.md](05-constraints.md) | Haiku | 900 | 7+ | 2026-04-25 |
| [06-completion-language.md](06-completion-language.md) | Haiku | 800 | 5+ | 2026-04-25 |
| [07-vault-structure.md](07-vault-structure.md) | Haiku | 1100 | 4+ | 2026-04-25 |
| [08-test-coverage.md](08-test-coverage.md) | Haiku | 900 | 6+ | 2026-04-25 |
| [09-anti-patterns.md](09-anti-patterns.md) | Haiku | 800 | 3+ | 2026-04-25 |
| [10-tier-selection-rules.md](10-tier-selection-rules.md) | Haiku | 500 | 10+ | 2026-04-25 |

**Total cache responses:** 10 queries  
**Average token cost per query (with cache):** 1K (vs 3K-5K without)  
**Cost savings per bootstrap:** ~20K tokens (70% reduction)

## Prompt Library (CLAUDE.md sections, cross-project)

*Pending Phase 4.2: Extract refined CLAUDE.md section prompts from three Strategix projects*

| Section | Status | Cached | Updated |
|---------|--------|--------|---------|
| Project | ✅ | [01-project-section-draft.md](01-project-section-draft.md) | 2026-04-25 |
| Purpose | ⏳ | — | — |
| Scope | ✅ | [02-scope-definition.md](02-scope-definition.md) | 2026-04-25 |
| Out of Scope | ✅ | [02-scope-definition.md](02-scope-definition.md) | 2026-04-25 |
| Constraints | ✅ | [05-constraints.md](05-constraints.md) | 2026-04-25 |
| Architecture Conventions | ✅ | [03-architecture-conventions.md](03-architecture-conventions.md) | 2026-04-25 |
| Completion Language | ✅ | [06-completion-language.md](06-completion-language.md) | 2026-04-25 |
| Anti-Patterns | ✅ | [09-anti-patterns.md](09-anti-patterns.md) | 2026-04-25 |

## When Cache Updates

- **Per-project**: When a new project-type discovers a novel pattern (e.g., CustomerA adds ops-intelligence variant)
- **Weekly**: Observability daemon updates cache hit rates, flags stale entries
- **On contradiction**: When cached answer conflicts with current code/state, refresh cache
- **Token analysis**: Token spend vs estimate shows if cache should be split/merged

## How Skill Uses Cache

**new-project-bootstrap v2:**
1. Step 2 (Project section): Query brain for "similar projects of this type"
   → Returns cached [01-project-section-draft.md]
   → Haiku can format answer, 800 tokens instead of Sonnet 3K
   
2. Step 3 (Scope + Out of Scope): Query brain for "Phase 1 scope for this project-type"
   → Returns cached [02-scope-definition.md]
   → Cost: 1200 tokens (cached) vs 4K tokens (Sonnet from scratch)
   
3. Step 5 (Architecture): Query brain for "conventions for this project-type"
   → Returns cached [03-architecture-conventions.md]
   → Cost: 1K tokens (cached) vs 3.5K tokens (Sonnet)

**Result:** Bootstrap uses Haiku throughout (cached responses), escalates to Sonnet only for RBAC design + contradiction pass.

## Cache Invalidation

Cache stays valid until:
- ❌ Related lesson changes (e.g., L-018 RBAC changes → invalidate [04-rbac-structure.md])
- ❌ Project template changes (e.g., service-desk scope changes → invalidate [02-scope-definition.md])
- ❌ New project-type discovered (add to cache, don't update existing entries)
- ✅ Token spend within 10% of estimate (cache still good, reuse)
- ✅ Cache hit rate >5 (cache paying for itself)

## Related
- **observability/token-spend-log.md** — tracks actual vs estimated costs
- **observability/bootstrap-quality-metrics.md** — tracks cache effectiveness (time-to-bootstrap, contradiction count, etc.)
- **bootstrap/project-types/** — source templates for cache entries
- **lessons/\*.md** — lessons referenced in cache (e.g., L-018, L-021)
