# Self-Improvement Loop Architecture

**Purpose:** Continuous autonomous refinement of lessons, prompts, tier selection, and caching based on observed patterns across all projects.

---

## Four-Layer Learning System

### Layer 1: Pattern Detection (Weekly)
**Input:** Findings from all projects, lesson application frequency, verdict distribution
**Process:**
- Analyze findings by scope (RBAC, schema, affordance, etc.)
- Count violations per lesson (L-018 violations: 2 in servicedesk, 1 in crm → pattern emerging)
- Track lesson effectiveness: predicted prevention vs actual prevention
- Detect false positives: lessons that trigger but don't apply

**Output:**
- `meta-patterns.md` — universal patterns (80%+ projects affected)
- `lesson-effectiveness-report.md` — which L-NNN actually work
- `anti-pattern-drift.md` — patterns that have regressed

### Layer 2: Feedback Refinement (Continuous)
**Input:** Developer corrections ("no, that's wrong"), agent verdicts, code review comments
**Process:**
- Capture inline corrections: `// L-018 violation, but not in this context because...`
- Extract reasoning from code reviews: `"This violates the rule from L-020, but we're accepting it because X"`
- Classify: Is this a lesson refinement, an exception, or a new lesson?

**Output:**
- `lesson-[NNN]-refinements.md` — contextual exceptions discovered in practice
- `new-lesson-candidates.md` — patterns that don't have lessons yet
- `prompt-library-updates.md` — refined prompts for bootstrap/tier selection

### Layer 3: Meta-Learning (Per-Customer)
**Input:** Lessons from all projects, cross-project synthesis
**Process:**
- Group lessons by problem class: RBAC lockout (L-018 + customerA-L-009 + customerB-L-002) → synthesis
- Extract meta-principles: "Multi-tenant systems always need X; single-tenant systems always need Y"
- Identify causal chains: "Schema drift → affordance drift → RBAC lockout" (three-lesson dependency)

**Output:**
- `universal-doctrine.md` — principles that apply to all projects
- `domain-patterns.md` — patterns specific to service-desk / revops / ops-intelligence
- `causal-chains.md` — dependencies between lessons

### Layer 4: Autonomous Tuning (Per-Query)
**Input:** Cached responses, token spend, model performance
**Process:**
- Track cache hit rates per query type
- Measure token cost per tier (Haiku vs Sonnet vs Opus)
- Detect tier downshift opportunities: "This query cached; Haiku can now answer it"
- Identify tier upgrades: "Opus took 3x longer than expected; need stronger reasoning"

**Output:**
- `tier-tuning.md` — when to shift models per query class
- `cache-invalidation-rules.md` — which lessons/findings invalidate which caches
- `cost-optimization.md` — Haiku-ifiable queries, batching opportunities

### Layer 5: Agent Observability (Continuous)
**Input:** Agent invocations, execution logs, output metrics
**Process:**
- Track frequency of each agent type (how often is bootstrap-executor vs code-reviewer vs cross-repo-change used?)
- Measure success rate per agent (% of invocations that complete without error)
- Monitor token spend per agent (cost-per-invocation across Haiku/Sonnet/Opus tiers)
- Detect over-triggering patterns (agent fire-and-forgets more than expected?)
- Flag error categories (validation failures, timeout, dependency issues)

**Output:**
- `agent-health.md` — success rate, frequency, cost, error patterns per agent
- `agent-alerts.md` — agents degrading, over-spending, under-triggering
- `agent-token-budget.md` — token cost per agent per month (cost attribution)

### Layer 6: Output QA (Gate Before Merge/Deploy)
**Input:** Autonomous agent outputs (code, docs, STATE.md updates)
**Process:**
- Validate code syntax + type safety (no compilation errors)
- Check test coverage (80%+ on code changes)
- Enforce shared invariants (L-018, currency suffixes, RBAC centralisation, no inline role arrays)
- Verify documentation updates (STATE.md updated if current-truth fact changed, AUTONOMY.md respected)
- Audit security (no hardcoded secrets, no SQL injection patterns, no XSS)
- Verify commit message quality (conventional commits, meaningful bodies)
- Check git hygiene (single logical commit per feature, no squash of unrelated changes)

**Output:**
- `qa-pass.md` — validated outputs ready for merge
- `qa-block.md` — outputs requiring human review/fix before merge
- `qa-findings.md` — classes of issues detected (most common: missing STATE.md update, test coverage gap, invariant violation)

---

## Automated Workflows

### Weekly Synthesis (Observability Rollup)
```
1. Ingest findings from all projects (findings/)
2. Run Layer 1 (pattern detection)
3. Update lesson-effectiveness.md
4. Detect new universal patterns
5. Flag lessons with low effectiveness
6. Commit changes to brain
```

### Continuous Feedback Loop (During Development)
```
1. Developer writes correction comment (L-NNN override reason)
2. Daemon parses correction during code review
3. Extracts refinement suggestion
4. Adds to lesson-[NNN]-refinements.md
5. Suggests prompt library update
6. Notifies if new lesson should be created
```

### Daily Meta-Learning Synthesis
```
1. Read all lessons from all projects
2. Group by problem class
3. Extract shared principles
4. Update universal-doctrine.md
5. Update domain-patterns.md
6. Detect causal chains (lesson dependencies)
```

### Continuous Cache Tuning
```
1. Monitor resolve-tier.mjs queries
2. Track cache hit rate per query
3. Measure token spend per model
4. If cache-hit-rate > 80%: mark query for Haiku downshift
5. If Opus runtime > 2x expected: mark for upgrade
6. Update tier-tuning.md rules
```

### Continuous Agent Observability Tracking
```
1. Log every agent invocation: agent-type, repo, start-time, end-time, tokens-used, model-tier, exit-code
2. Aggregate weekly: success-rate, token-cost, frequency per agent
3. Flag if success-rate < 95% (needs investigation)
4. Flag if cost > baseline (this agent unexpectedly expensive?)
5. Flag if frequency << expected (agent under-triggered? condition needs widening?)
6. Flag if frequency >> expected (agent over-triggered? refine trigger logic?)
7. Update agent-health.md with findings
```

### Continuous Output QA Validation
```
1. On every agent output (code, docs, STATE.md update):
   a. Run syntax check (tsc, prettier, eslint)
   b. Run test suite (must pass, coverage >= 80%)
   c. Check shared invariants (RBAC central, currency suffixes, L-018/L-025)
   d. Check docs alignment (STATE.md updated if truth fact changed)
   e. Check security (no hardcoded secrets, parameterized queries)
   f. Audit git (conventional commits, single logical commit)
2. If all checks pass: mark qa-pass, ready for merge
3. If any check fails: mark qa-block, log to qa-findings.md, notify orchestrator
4. Trend analysis: which check-types fail most? (suggests lesson gap or agent misconfiguration)
```

---

## Data Models

### Pattern Entry (`meta-patterns.md`)
```yaml
---
id: rbac-lockout-universal
title: RBAC Lockout is a Universal Problem
scope: [RBAC, multi-project]
occurrence_rate: "80%"
lessons_involved: [strategix-L-018, customerA-L-009, customerB-L-002]
causal_chain: "role-array-inline → centralization-skip → lockout"
confidence: 0.95
---
```

### Lesson Effectiveness Entry (`lesson-effectiveness.md`)
```yaml
---
lesson_id: strategix-L-018
title: "No inline role arrays"
violations_since_capture: 3
prevented_since_capture: 18
prevention_rate: 0.86
false_positive_rate: 0.05
status: EFFECTIVE
last_refined: 2026-04-25
---
```

### Feedback Refinement (`lesson-[NNN]-refinements.md`)
```yaml
---
lesson_id: strategix-L-018
refinement_discovered: 2026-04-25
context: "crm uses inline role constants in src/lib/constants.ts — not a violation"
exception_rule: "Inline arrays in routes are forbidden; inline arrays in constants.ts are the pattern"
affects_projects: [crm]
new_lesson_candidate: "crm-L-NNN: Role constants must centralize but are not checked on every route"
---
```

### Tier Tuning Entry (`tier-tuning.md`)
```yaml
---
query_class: "Bootstrap CLAUDE.md section: [section-name]"
cached: true
cache_hit_rate: 0.92
model_history: [Opus, Sonnet, Sonnet, Sonnet, Sonnet, ...]
recommended_model: Haiku
cost_per_run_opus: "~8K tokens"
cost_per_run_haiku: "~2K tokens"
annual_savings_if_downshifted: "~$180 per customer"
---
```

### Agent Health Entry (`agent-health.md`)
```yaml
---
agent_id: code-reviewer
agent_type: Code review / verification
invocation_count_month: 47
success_rate: 0.98  # 46/47 completed without error
provider_breakdown:
  - provider: Claude (Haiku)
    invocations: 20
    success_rate: 1.0
    avg_tokens: 8500
  - provider: Codex (gpt-5)
    invocations: 15
    success_rate: 0.93
    avg_tokens: 24000
  - provider: Gemini (3.1-pro)
    invocations: 12
    success_rate: 0.92
    avg_tokens: 19500
avg_tokens_per_invocation: 18500
total_tokens_month: 870500
cost_estimate: "~$6.50/invocation (multi-provider avg)"
error_categories: [timeout: 1]
last_failure: "2026-04-25 14:32 — timeout on 45-file refactor (Codex)"
performance_alert: null
efficiency_alert: "Codex slightly high variance (24K tokens vs Haiku 8.5K); consider tier-tuning"
status: HEALTHY
---
```

### QA Finding Entry (`qa-findings.md`)
```yaml
---
timestamp: 2026-04-25T14:30:00Z
agent_output: "code-reviewer verdict on PR #127"
qa_status: BLOCK
blocked_reason: "Test coverage dropped from 84% to 71%"
checks_passed: [syntax, security, invariants, git-hygiene]
checks_failed: [test-coverage]
recommendation: "Agent output requires test additions before merge"
issue_link: null
trend: "test-coverage gaps in 3/last-10 outputs from this agent"
---
```

---

## Implementation Hooks

### In Every Agent's PostToolUse Hook
- Log invocation: agent-type, repo, start-time, end-time, tokens-used, model-tier, exit-code
- On error: categorize (timeout, validation, dependency, etc.)
- Update agent-health.md aggregates weekly

### In `resolve-tier.mjs`
- Track query type + model used + token spend
- On cache hit, recommend Haiku downshift
- Update tier-tuning.md with findings

### In Code Review Agents
- Parse developer corrections: `// L-NNN: override because ...`
- Extract refinement suggestion
- Flag for lesson update

### In QA Validation Layer (PostToolUse, Before Merge Gate)
- Run syntax check (tsc, prettier, eslint)
- Run test suite: must pass, coverage >= 80%
- Validate shared invariants (shared-stack-invariants, RBAC, suffixes, L-018/L-025)
- Verify docs (STATE.md updated, AUTONOMY.md respected, git hygiene)
- Check security (no hardcoded secrets, parameterized queries)
- If all pass: mark qa-pass, ready for merge
- If any fail: mark qa-block, log to qa-findings.md, notify orchestrator

### In Observability Rollup Daemon
- Weekly: run pattern detection, update effectiveness, synthesize meta-lessons
- Weekly: aggregate agent-health data from all invocations
- Weekly: trend qa-findings to detect systematic issues (e.g., "test coverage drops more often after bootstrap agent runs")
- Daily: synthesize meta-learning, detect causal chains
- Continuous: cache tuning feedback

### In Lesson Ingestion
- On lesson creation: check if it matches a meta-pattern (don't duplicate)
- On lesson update: invalidate related caches (tier-tuning, bootstrap-templates)
- On lesson update: flag if QA-findings suggest this lesson is under-preventing (high violation rate despite lesson existence)

---

## Feedback Loops Enabled

1. **Prevention Improvement**: Low-effectiveness lessons are refined or retired
2. **Prompt Optimization**: Cached responses inform prompt library updates
3. **Tier Optimization**: High-hit-rate queries auto-downshift to cheaper models
4. **Universal Doctrine**: Meta-patterns apply to new customers immediately
5. **Causal Understanding**: Lessons update their dependencies as chains are discovered
6. **Agent Health Optimization**: Observability agent tracks which agents work well, which over-trigger, which are under-utilized → adjust trigger conditions and frequency
7. **Quality Gate Enforcement**: QA agent blocks merges that violate invariants, skip tests, miss docs → prevents regressions from autonomous work
8. **Systematic Issue Detection**: QA findings trend analysis reveals if certain agents consistently fail the same checks → suggests need for agent retraining or lesson creation

---

## Output: Self-Improving Brain

The Obsidian Brain evolves:
- **Week 1:** Observes strategix-L-018 violations, improves wording
- **Week 2:** Notices pattern across crm + ioc, creates universal principle
- **Week 3:** New customer joins, brain suggests strategix-L-018 because meta-pattern triggers
- **Week 4:** Cached bootstrap prompt reduces from Opus → Haiku, saves cost
- **Week 8:** Lesson effectiveness report shows L-018 now prevents 95% of incidents; automatic refinement paid off

---

## Autonomous Without Human Intervention

Self-improvement runs continuously:
- Pattern detection → automatic (no human approval needed to detect)
- Feedback parsing → automatic (extracts from code, comments, verdicts)
- Meta-learning synthesis → automatic (groups lessons, finds patterns)
- Tier tuning → automatic (updates tier-tuning.md, resolve-tier.mjs reads it)
- **Agent observability → automatic (logs every invocation, tracks health, flags degradation)**
- **Output QA → automatic (validates before merge: syntax, tests, invariants, docs, security)**

Quality gates enabled by observability + QA agents:
- ✓ Autonomous agents can write code/docs to autonomous-safe branches
- ✓ QA agent validates output meets 80%+ test coverage, no invariant violations, no security gaps
- ✓ If QA passes: merge immediately (no human review needed for pre-validated agent work)
- ✓ If QA fails: block merge, log issue, notify orchestrator
- ✓ Observability agent tracks which QA checks fail most often → informs lessons and agent training

**Human role:** 
1. Review weekly synthesis reports (pattern detection, agent health, QA trends)
2. Accept/reject major lesson refinements or new lessons (major policy changes)
3. Audit QA-blocked outputs if patterns suggest systematic issues
4. Decide when to retrain or retire agents based on observability metrics

