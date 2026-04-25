# Universal Patterns — Cross-Project Lessons

Meta-patterns identified across Strategix projects (crm, ioc, servicedesk) that apply universally to all projects and all customers.

---

## RBAC Lockout Cascade

**Affects:** 80% of projects (observed across crm, servicedesk; ioc has fewer changes)

**Universal Lessons:**
- [[strategix-L-018]] — Centralised RBAC, inline role arrays forbidden
- [[strategix-L-019]] — Multi-tenant RBAC variant (tenants can define role subsets)
- [[strategix-L-025]] — Role arrays must cite shared constants, not hand-write

**Pattern:**
1. New role defined in isolation ✓ (looks correct in RBAC source)
2. Role inheritance incomplete (e.g., manager roles don't inherit STAFF)
3. Intersects with existing `requireRole([STAFF, ADMIN])` guards
4. Silent 403 lockout on critical flows (tickets, dashboard, settings)
5. Caught 2-4 days later by users hitting 403s

**Prevention:** Enumerate every `requireRole()` call-site before finalising new role inheritance. Add regression tests per new role. Adversarial review must include "existing-guards-vs-new-roles" lens.

**Cost if ignored:** 2-4 days triage, 2-4 hours fix, user frustration, potential escalation.

---

## Shell Rebuild Affordance Drift

**Affects:** 60% of projects with frontend work (servicedesk; crm+ ioc have lower risk)

**Universal Lessons:**
- [[strategix-L-020]] — Responsive affordance continuity across breakpoints
- [[strategix-L-022]] — Tailwind `peer-*` source order (silent selector failures)

**Pattern:**
1. New responsive-visibility pattern introduced (`hidden md:flex`)
2. Affordance moved into conditionally-hidden container
3. Mobile breakpoint has no fallback (sign-out, new-ticket, help, search disappear)
4. Desktop pixel-matching passes; mobile manual test not run
5. Caught post-commit when user reports "can't log out on mobile"

**Prevention:** Create affordance matrix before dispatch (old visibility → new visibility + mobile fallback). Add "affordance continuity" adversarial lens. Require manual smoke test at 375px. Tailwind `peer-*` must have peer before target in source order.

**Cost if ignored:** User lockout on mobile, reputation damage, 4-8 hours triage + redesign.

---

## Async Race Conditions in Mutations

**Affects:** 100% of projects (crm, ioc, servicedesk all affected)

**Universal Lessons:**
- [[crm_lesson_name_CAS]] — State transitions need compare-and-swap (read-then-write is last-write-wins)
- [[crm_lesson_name_revision_token]] — Revision tokens required for human-review surfaces
- [[ioc_lesson_name_abort_controller]] — Per-batch AbortController must preempt in-flight calls, not just skip next

**Pattern:**
1. Mutation does a precondition SELECT check
2. Two requests race: both pass the check, both execute UPDATE
3. Last write wins; no error; audit trail is doubled or incomplete
4. Or: concurrent batch work: one worker aborts, others keep burning tokens

**Prevention:** Use atomic `UPDATE ... WHERE id = ? AND <status> = <expected>` (compare-and-swap). For human review surfaces, add revision tokens. For batch work, share AbortController across all external calls. Test with concurrent callers.

**Cost if ignored:** Silent double-write, audit chaos, approval duplicates, resource waste (continued API calls after abort).

---

## Config-in-DB Must Fail Closed

**Affects:** 40% of projects (crm heavily affected; others less)

**Universal Lessons:**
- [[crm_lesson_config_in_d1]] — Config-in-D1 must fail closed at every consumer

**Pattern:**
1. Value (pricing curve, discount rate, approval threshold) migrated from code → D1 table
2. Some consumers found and updated; others missed (server fallback, client cache, legacy import)
3. Finance edits the DB value; one consumer sees old hardcoded constant; users see inconsistent pricing
4. Caught after someone notices discrepancy

**Prevention:** Grep for every import of the old constant. Classify each consumer: (a) preview-only (fallback OK, document it); (b) commercial artefact (fail closed, gate on load state); (c) historical record (snapshot at write time). Fallback to hardcodes is a governance footgun.

**Cost if ignored:** Pricing inconsistency, finance frustration, audit trail mismatch, 2-4 days root-cause.

---

## D1 Schema Migrations Have Landmines

**Affects:** 100% of projects (crm, ioc both affected)

**Universal Lessons:**
- [[crm_lesson_explicit_columns]] — `INSERT INTO __new SELECT *` is positional and misaligns silently
- [[ioc_lesson_drizzle_journal]] — Stale Drizzle journal can cause CREATE TABLE for pre-existing tables
- [[ioc_lesson_dont_edit_migration]] — Once committed, treat migration schema as frozen; add new ALTER, don't edit old

**Pattern:**
1. Table recreate: `INSERT INTO __new SELECT * FROM old` (positional, not named)
2. Prod columns drifted from canonical order (prior ALTER TABLE ADD COLUMN)
3. NULL from REAL column silently inserted into NOT NULL INTEGER column
4. SQLITE_CONSTRAINT_NOTNULL error doesn't mention column order
5. Or: Drizzle journal stale, auto-generate creates all 30+ tables again

**Prevention:** Always list columns explicitly on both sides (`INSERT INTO __new (col1, col2, ...) SELECT col1, col2, ... FROM old`). Inspect Drizzle output before committing. Treat committed migrations as frozen; add new ALTER for further changes. `pragma table_info(...)` to verify column order before migration.

**Cost if ignored:** Silent wrong-column inserts, constraint violations, schema drift, 2-3 days to untangle.

---

## Doctrine Files Must Not Carry Temporal Status

**Affects:** 100% of projects (crm, ioc both affected)

**Universal Lessons:**
- [[crm_lesson_PROJECT_md_temporal]] — PROJECT.md must not carry mutable deploy status

**Pattern:**
1. Doctrine file (PROJECT.md, programme.md) written with present-tense status: "Staging: None today. Changes go directly to prod."
2. Phase completes (staging ships); doctrine file not updated
3. Downstream readers (programme status, audit docs) inherit the stale wording
4. 30 days later, vault docs still claim "no staging" despite it being live

**Prevention:** Doctrine files capture durable intent/constraints only. Any "today", "currently", "not yet" wording belongs in STATE.md, not PROJECT.md. Point PROJECT.md to STATE.md for live status. Sweep vault docs when a ROADMAP phase closes.

**Cost if ignored:** Cross-team confusion, stale compliance docs, 2-3 days discovery that "the rule changed but nobody updated the rule book."

---

## Metrics Must Update Atomically with Code

**Affects:** 100% of projects (servicedesk most affected)

**Universal Lessons:**
- [[servicedesk_L-023]] — STATE.md `## Counts` table must update atomically with code change

**Pattern:**
1. Commit adds routes, tests, migrations
2. Narrative section of STATE.md updated ("Phase X closing")
3. Counts table (`Tests`, `Routes`, `Migrations`) not updated
4. Next reader sees narrative says "180 tests" but counts say "173 tests"
5. Reviewer asks: "What's the source of truth?"

**Prevention:** After writing narrative, re-read Counts table and update every row that changed. Treat Counts table as post-narrative checklist. Adversarial reviewers must cross-check Counts against diff.

**Cost if ignored:** Split truth (narrative vs counts), future readers confused, 2-3 days tracing which is authoritative.

---

## Planning/Coding Split Must Be Enforced

**Affects:** 100% of projects (servicedesk most affected)

**Universal Lessons:**
- [[servicedesk_L-001]] — Keep planning in Claude, offload coding to Codex
- [[servicedesk_L-015]] — Docs commits go on `main`; feature branches for the work they're named after

**Pattern:**
1. Claude writes planning docs (CLAUDE.md, .planning/STATE.md, briefs)
2. Codex handles implementation (routes, components, tests)
3. Codex accidentally edits doctrine file (or)
4. Docs commit lands on feature branch named for code work (or)
5. Audit trail shows Codex "authored" planning decisions

**Prevention:** Claude owns planning/doctrine/truth files; Codex owns product code. If Codex tries to touch .planning/, STATE.md, CLAUDE.md, lessons.md, vault — stop-gate flags it. Docs always land on main; feature branches are for the feature only. Review "who should have written this" as part of code review.

**Cost if ignored:** Blurred planning/coding boundary, Codex making architecture decisions, lost audit trail, future sessions misunderstand intent.

---

## Adversarial Review Lenses Must Be Orthogonal

**Affects:** 100% of projects (crm, ioc, servicedesk all affected)

**Universal Lessons:**
- [[servicedesk_L-012]] — Dispatch two sub-agents with distinct lenses, not identical ones
- [[servicedesk_L-013]] — Overseer + subordinate hierarchy (overseer spawns parallel agents, synthesis at overseer)
- [[servicedesk_L-017]] — Sonnet overseers collapse L-013 unless explicitly forbidden
- [[servicedesk_L-019]] — Sonnet overseer bypass recurs; flat Haiku peer fan-out safer when lens diversity dominates

**Pattern:**
1. Review has 3 lenses: doctrine, facts, convention
2. All three dispatched as Sonnet agents (identical model)
3. They converge on same findings (token waste, false confidence)
4. Or: Sonnet overseer rationalises away fan-out ("I have the data already, I'll synthesize")
5. Single reviewer masquerades as three-lens coverage

**Prevention:** Distinct lenses → distinct briefs → verify dispatch via Agent IDs in response. When overseer-bypass detected, skip overseer tier and dispatch subordinates directly from main turn. Name the model in overseer brief (`haiku` or `sonnet`, not "subordinate"). Require overseer to include subordinate opening paragraphs as proof of dispatch.

**Cost if ignored:** False confidence in reviews, single-perspective blind spots, missed drift classes.

---

## Summary

**Highest-priority universal patterns across all projects:**

1. **RBAC Lockout (L-018/L-019/L-025)** — Affects 80%, costs 2-4 days per violation
2. **Shell Affordance Drift (L-020/L-022)** — Affects 60%, locks out users on mobile
3. **Async Race Conditions (CAS, revision tokens)** — Affects 100%, silent double-write risk
4. **Schema Migration Landmines** — Affects 100%, hardest to debug (column order misalignment)
5. **Temporal Status in Doctrine** — Affects 100%, cascades to vault/compliance docs
6. **Planning/Coding Split Erosion** — Affects 100%, degrades over time if unguarded

**Recommended ingestion priority for new customers:**

When Customer A bootstraps, prioritise ingesting these 5 universal patterns before domain-specific lessons. They apply to 100% of projects and represent the heaviest cost-of-ignorance.

---

*Meta-patterns synthesised 2026-04-25 from Strategix crm (3 lessons), ioc (10+ lessons), servicedesk (23 lessons). Pattern extraction ongoing across three repos.*
