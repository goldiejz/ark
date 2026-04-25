# Tier Selection Rules (Phase 7) — Multi-Model Offloading

**Last updated:** 2026-04-25

## Decision Tree (Extended with Codex + Gemini)

```
Is there a cached response for this query?
  ├─ YES → Use HAIKU ($0.06/KT, 800 tokens)
  │   └─ Confidence: 100%
  │
  └─ NO → Task characteristics?
      │
      ├─ MULTI-FILE CODE REFACTOR (large codebase, multi-repo)?
      │   ├─ Use CODEX ($0.12/KT, large-file expertise, 8s latency)
      │   └─ Fallback: SONNET ($0.20/KT) or HAIKU
      │
      ├─ CROSS-PROJECT SYNTHESIS (universal patterns, broad reasoning)?
      │   ├─ Use GEMINI ($0.06/KT, wide knowledge, 6s latency)
      │   └─ Fallback: SONNET ($0.20/KT)
      │
      ├─ DEEP NOVEL REASONING (architecture, first-time problem)?
      │   ├─ Use OPUS ($0.32/KT, deep reasoning, 10s latency)
      │   └─ Fallback: SONNET ($0.20/KT)
      │
      ├─ TEST GENERATION (code-heavy, deterministic)?
      │   ├─ Use CODEX ($0.12/KT, test expertise)
      │   └─ Fallback: SONNET ($0.20/KT)
      │
      └─ DEFAULT (balanced dev work, reasoning + code)?
          ├─ Use SONNET ($0.20/KT, best all-rounder, 5s latency)
          └─ Fallback: HAIKU (if simple), OPUS (if complex)
```

## Model Economics & Strengths

| Model | Cost/KT | Latency | Strengths | Best For |
|-------|---------|---------|-----------|----------|
| **Haiku** | $0.06 | 2s | Lightweight, fast cached responses | Cached bootstrap, pair programming |
| **Sonnet** | $0.20 | 5s | Balanced reasoning + code, all-rounder | Main dev, code generation, orchestration |
| **Opus** | $0.32 | 10s | Deep novel reasoning, architecture | Novel architectural decisions, deep research |
| **Codex** | $0.12 | 8s | Large codebase analysis, multi-file refactoring | Code refactoring, test generation, multi-repo changes |
| **Gemini** | $0.06 | 6s | Broad knowledge synthesis, cross-domain patterns | Pattern synthesis, doc generation, research |

## Task Type → Model Mapping

### Bootstrap Phase (Cached)
- `01-project-section-draft` → **Haiku** (100% cache hit)
- `02-scope-definition` → **Haiku** (100% cache hit)
- `03-architecture-conventions` → **Haiku** (100% cache hit)
- `04-rbac-structure` → **Sonnet** (cached context saves 30%)
- `05-constraints` → **Haiku** (100% cache hit)
- `06-completion-language` → **Haiku** (100% cache hit)
- `07-vault-structure` → **Haiku** (80% cache hit)
- `08-test-coverage` → **Haiku** (100% cache hit)
- `09-anti-patterns` → **Haiku** (100% cache hit)

### Refactoring & Code Changes
- Small file edits (<500 lines) → **Sonnet**
- Multi-file refactors (>2000 lines, multi-repo) → **Codex**
- Large codebase analysis (>50K LOC) → **Codex**
- Test generation → **Codex**

### Research & Synthesis
- Cross-project pattern synthesis → **Gemini**
- Lesson effectiveness analysis → **Gemini**
- Documentation generation → **Gemini**

### Architectural & Novel Decisions
- New architecture patterns → **Opus**
- First-time problem solving → **Opus**
- Deep design review → **Opus**

## Model Distribution Target

After 3 months of maturity:

```
Haiku:  40% (cached responses)
Sonnet: 35% (balanced dev work)
Codex:  15% (code-heavy tasks)
Gemini: 8%  (cross-project synthesis)
Opus:   2%  (novel architecture)
```

## Cost Model: Before & After Multi-Model

| Scenario | Haiku | Sonnet | Opus | Codex | Gemini | Total |
|----------|-------|--------|------|-------|--------|-------|
| **All Sonnet (no brain)** | 0 | 25,000 | 0 | 0 | 0 | 25,000 |
| **Phase 4-5 (cached)** | 8,200 | 5,000 | 0 | 0 | 0 | 13,200 |
| **Phase 7 (Sonnet only)** | 8,000 | 3,500 | 400 | 0 | 0 | 11,900 |
| **Phase 7 (Multi-model)** | 8,000 | 2,500 | 300 | 800 | 500 | **12,100** |

**Key insight:** Multi-model doesn't reduce cost much vs Sonnet-only, but **improves quality** by using specialized models for their strengths:
- Codex excels at large refactors (faster, better code)
- Gemini excels at synthesis (broader knowledge)
- Opus excels at novel reasoning (deeper analysis)

## Phase 5 Integration

In `new-project-bootstrap-v2.ts`:

```typescript
import { createMultiModelResolver } from '../observability/phase-7-multi-model-resolver';

const resolver = createMultiModelResolver();

// Example: Step 5 RBAC Design
const taskCharacteristics = {
  taskType: 'rbac-design',
  reasoningDepth: 'medium',
  breadthRequired: 'wide',
  needsContextAwareness: true,
  isCached: false,
  pastExecutions: 8,
  hasMultiRepoContext: true
};

const recommendation = resolver.resolveMultiModel('04-rbac-structure', taskCharacteristics);
console.log(`Using ${recommendation.model} (${recommendation.provider}): ${recommendation.reason}`);

// Execute with chosen model
const result = await executeWithModel(recommendation.model, prompt);
```

## Decision Recording (Phase 6 Feedback)

Each bootstrap records:
1. Query ID (`01-project-section-draft`, etc.)
2. Model used (haiku, sonnet, codex, gemini, opus)
3. Actual tokens consumed
4. Execution time
5. Cache hit (yes/no)

Weekly observability roll-up analyzes:
- Which models are actually being used
- Which task types benefit from Codex vs Sonnet
- Which cross-project patterns trigger Gemini vs Sonnet
- Cost/quality tradeoffs

## Observability Metrics

Track per week:

- Cache hit rate by query type
- Model distribution (H/S/C/G/O ratio)
- Average tokens per task type
- Cost per task type (including model overhead)
- Quality metrics (correctness, rework rate, clarity)
- Novel task discovery rate (tasks that don't fit known patterns)

---

*This document is auto-updated by Phase 6 observability daemon weekly.*
