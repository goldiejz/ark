---
phase: 5
title: "Phase 5: new-project-bootstrap v2 Integration Design"
date: 2026-04-25
status: "Planning (ready to implement)"
---

# Phase 5: Wire new-project-bootstrap Skill to Brain Cache

## Overview

**Goal:** Make new-project-bootstrap skill query Obsidian brain for templates, cached responses, and contradiction detection.

**User benefit:** New projects bootstrap 40% faster (via templates + cached responses), with fewer contradictions caught pre-merge.

**Cost savings:** Haiku handles most bootstrap steps (cached responses, 800 tokens) instead of Sonnet (3K tokens).

---

## Current Flow (Bootstrap v1)

```
User: "Create a new [project-type] project"
  ↓
new-project-bootstrap skill activates
  ↓
1. Read doctrine (project-standard.md, programme.md)
2. Confirm purpose (check PROJECT.md scope is crisp)
3. Execute 12-step checklist:
   - Create repo
   - Draft CLAUDE.md sections
   - Populate .planning/
   - Create vault skeleton
   - Wire auth
   - etc.
4. Check contradictions (manual via contradiction-pass skill)
```

---

## Enhanced Flow (Bootstrap v2)

```
User: "Create a new [project-type] project for [customer] [role]"
  ↓
new-project-bootstrap v2 activates
  ↓
[STEP 0: QUERY BRAIN FOR CONTEXT]
  Query 1: "What similar projects exist? What did they decide?"
    ↓ Returns: [cached] list of projects of same type + their key decisions
  Query 2: "What anti-patterns should I watch for [project-type]?"
    ↓ Returns: [cached] 09-anti-patterns.md + relevant L-NNN entries
  Query 3: "What vault structure worked well for [domain]?"
    ↓ Returns: [cached] 07-vault-structure.md + customization per domain
  ↓
[STEP 1: RESOLVE PURPOSE (same as v1, but brain-informed)]
  Confirmation: "Is project scope crisp? Any contradictions with similar projects?"
  Brain input: "Here's what similar projects chose for this decision"
  ↓
[STEP 2-11: EXECUTE BOOTSTRAP (brain-assisted)]
  Step 3 (Draft CLAUDE.md Project section):
    Query brain: [01-project-section-draft.md]
    Haiku formats answer (800 tokens) instead of Sonnet (3K tokens)
    Cost: 66% reduction
  
  Step 4 (Draft Scope + Out of Scope):
    Query brain: [02-scope-definition.md]
    Haiku formats (1.2K tokens) instead of Sonnet (4K tokens)
    Cost: 70% reduction
  
  Step 5 (Architecture Conventions):
    Query brain: [03-architecture-conventions.md]
    Haiku with context (1K tokens) instead of Sonnet (3.5K tokens)
    Cost: 71% reduction
  
  Step 7 (RBAC Design):
    Sonnet queries: [04-rbac-structure.md] + project-type template
    Enhanced: Brain provides role matrix + permission patterns
    Cost: 30% reduction (Sonnet + cached context faster than fresh design)
  
  Step 8 (Vault Structure):
    Query brain: [07-vault-structure.md]
    Haiku customizes per domain (1.1K tokens) instead of Sonnet (3K tokens)
    Cost: 63% reduction
  
  Step 10 (Test Strategy):
    Query brain: [08-test-coverage.md]
    Haiku adapts for project-type (900 tokens) instead of Sonnet (2K tokens)
    Cost: 55% reduction
  ↓
[STEP 12: CONTRADICTION PRE-CHECK]
  Query brain: [09-anti-patterns.md] for [project-type]
  Create checklist of known contradiction patterns
  Flag any pre-merge (instead of post-launch)
  Cost: Haiku pre-check (500 tokens) vs Sonnet post-hoc analysis (3K tokens)
  ↓
[STEP 13: DECISION LOG]
  Record every decision made by bootstrap
  → Feeds into observability daemon (Phase 6) for cross-project pattern detection
  → Updates lesson effectiveness tracking
  ↓
[FINALIZE: SUGGEST RELATED LESSONS]
  "This project-type has these active lessons (L-NNN). Familiarize your team."
  Example: "Service Desk projects: L-018 (RBAC), L-021 (route/compute), L-020 (manager narrowing)"
```

---

## Portability First

**Critical:** This design works for LOCAL projects AND Claude Cowork projects. Bootstrap queries embedded snapshot (`.parent-automation/brain-snapshot/`), not direct file reads. This enables:
- Offline bootstrap (no network needed)
- Claude Cowork projects (no ~/vaults access)
- Portable automation (copy to any directory, works)
- Optional central brain (refresh snapshot when network available)

See `phase5-portability-spec.md` for detailed architecture.

---

## Implementation Details

### 1. Brain Query Interface (Local Snapshot)

Bootstrap queries local snapshot at `.parent-automation/brain-snapshot/`:

```typescript
// Uses embedded snapshot, not ~/vaults/
const snapshot = await readSnapshot('.parent-automation/brain-snapshot/');
const cached = snapshot.get('01-project-section-draft');
```

Fallback to network (optional):
```typescript
if (snapshot.isStale() && hasNetworkAccess()) {
  const fresh = await fetch(process.env.BRAIN_API_URL + '/query/01-project-section-draft');
  await updateSnapshot(fresh);
}
```

```bash
/brain query 01-project-section-draft \
  --project-type service-desk \
  --project-name "CustomerA Service Desk" \
  --customer customerA

# Returns:
# - Cached CLAUDE.md Project section template
# - Examples from similar projects (if any)
# - Related lessons (L-NNN) and anti-patterns
# - Suggested next step
```

### 2. Integration Points in Bootstrap Skill

Modify new-project-bootstrap 12-step checklist:

**Step 1: Resolve Purpose**
```
+ NEW: Query brain for similar projects
  prompt: "I'm building a [project-type] for [customer]. 
           What key decisions did similar projects make?"
  response: Suggests scope boundaries, reveals common contradictions
```

**Step 3: Draft CLAUDE.md → Project Section**
```
OLD: "Draft the Project section. Describe: name, role, aspiration, siblings."
+ NEW: Query brain for [01-project-section-draft.md]
       "Haiku, here's the cached template. Adapt for our project."
       Haiku returns: [formatted Project section, 1-2 sentences]
       Cost: 800 tokens vs Sonnet 3K
       Time: 30s vs 5 min
```

**Step 4: Draft CLAUDE.md → Scope**
```
OLD: "Define Phase 1 features and Phase 2+ deferrals."
+ NEW: Query brain for [02-scope-definition.md]
       Match project-type features to our domain
       Haiku adapts template (1.2K tokens) vs Sonnet (4K tokens)
       Time: 1 min vs 10 min
```

**Step 5: Architecture Conventions**
```
OLD: "List critical conventions for this project."
+ NEW: Query brain for [03-architecture-conventions.md]
       Filter by project-type (service-desk vs revops vs ops-intelligence)
       Haiku applies conventions + cites related L-NNN lessons
       Time: 2 min vs 15 min
```

**Step 8: Vault Structure**
```
OLD: "Create vault skeleton with docs."
+ NEW: Query brain for [07-vault-structure.md]
       Haiku customizes for domain (Architecture/, Operations/, Domain/, etc.)
       Pre-populate README templates from brain
       Time: 5 min vs 30 min
```

**Step 11: Contradiction Pre-Check (NEW)**
```
NEW: Query brain for [09-anti-patterns.md]
     Create pre-merge checklist: "Avoid these for [project-type]"
     Example:
     ☐ Claiming "production-ready" (check: are we pitch-ready?)
     ☐ Inline role arrays in routes (check: RBAC centralized?)
     ☐ Trusting body-supplied tenant_id (check: using session?)
     
     Run contradiction-pass skill with anti-pattern checklist
     Flag contradictions BEFORE merge (not after launch)
     Time: 5 min vs 2 hours (if discovered post-launch)
```

**Step 13: Decision Log (NEW)**
```
NEW: Record bootstrap decisions for observability daemon
     - Project type: [service-desk|revops|ops-intelligence]
     - Customer: [strategix|customerA|customerB]
     - Key choices: (scope boundaries, auth mechanism, deployment target)
     - Contradictions found + resolved: (list any)
     - Lessons applied: (which L-NNN guided decisions?)
     → Feeds into Phase 6 (observability daemon)
```

### 3. Skill-to-Skill Communication

Bootstrap skill calls brain via:

```
// pseudocode
async function bootstrapStep(stepNum, context) {
  const query = BOOTSTRAP_QUERIES[stepNum]; // e.g., "02-scope-definition"
  const cached = await queryBrain(query, {
    projectType: context.projectType,
    customer: context.customer,
    domain: context.domain,
  });
  
  if (cached) {
    // Use Haiku to format cached response
    return await haiku.generate(cached.template, context);
  } else {
    // Cache miss: use Sonnet, then cache result
    const generated = await sonnet.generate(...);
    await brainCache.store(query, generated);
    return generated;
  }
}
```

### 4. Error Handling

**Cache miss:**
```
Query: "02-scope-definition" for "custom-analytics" project-type
Result: No cached response (new project-type)
Action: Sonnet generates scope definition, caches it for next time
Cost: 4K tokens this time, 1.2K tokens next time
```

**Contradiction detected in pre-check:**
```
Step 11: contradiction-pass finds: "RBAC guard missing on /approve route"
Brain reference: "L-018: RBAC Enum Completeness — prevent this exact issue"
Action: Flag contradiction, require resolution before merge
Result: Bug caught pre-launch (costs <5 min fix) vs post-launch (costs 20 hours debug + customer impact)
```

---

## Success Metrics (Phase 5)

By end of Phase 5:

- [ ] new-project-bootstrap v2 queries brain for all 10 cached responses
- [ ] Bootstrap uses Haiku for 60% of steps (cached responses)
- [ ] Bootstrap uses Sonnet for 30% of steps (RBAC, complex decisions)
- [ ] Bootstrap uses Opus for 0% of steps (no novel decisions yet in Phase 1)
- [ ] Pre-merge contradiction check runs automatically
- [ ] Decision log recorded for all bootstraps
- [ ] Token spend reduced from 25K → 15K per bootstrap (40% reduction)
- [ ] Time-to-bootstrap reduced from 4 hours → 2.5 hours
- [ ] Contradiction detection time reduced from 2 hours (post-launch) → 5 min (pre-merge)
- [ ] First Strategix project re-bootstrapped with v2 (verify: faster, fewer contradictions)

---

## Implementation Roadmap

**Day 1 (4 hours):**
1. Create `/brain query` command in parent automation
2. Implement cache retrieval logic
3. Modify new-project-bootstrap steps 1-5 to query brain
4. Test with mock queries

**Day 2 (3 hours):**
1. Complete bootstrap wiring for steps 6-10
2. Implement contradiction pre-check step
3. Add decision log recording
4. Test full bootstrap flow with mock project

**Day 3 (2 hours):**
1. Integrate observability daemon input
2. Measure token spend vs estimate
3. Bootstrap first real project (Strategix or customer A)
4. Verify metrics (speed, contradictions, token savings)

---

## Phase 5 → Phase 6 Transition

After Phase 5 complete, Phase 6 (observability daemon) will:
1. Read decision logs from all bootstraps
2. Detect cross-project patterns ("all 3 projects chose D1 for database")
3. Update lesson effectiveness ("L-018 prevented 5 RBAC incidents across projects")
4. Update cache hit rates
5. Flag stale cache entries for refresh

---

## Related
- **cache/MEMORY.md** — query response index
- **bootstrap/project-types/** — source templates for cache
- **lessons/\*.md** — lessons applied during bootstrap (L-NNN)
- **observability/lesson-effectiveness.md** — tracking which lessons work
