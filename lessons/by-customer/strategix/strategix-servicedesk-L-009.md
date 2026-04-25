---
id: strategix-servicedesk-L-009
title: When session budget tightens, hand off via brief + durable state, not verbal summary
date_captured: 2026-04-22 (evening)
origin_project: strategix-servicedesk
origin_repo: servicedesk
scope: ["process", "delivery"]
severity: HIGH
applies_to_domains: ["*"]
customer_affected: [strategix]
universal: true
---

## Rule

- **Always** at a session-budget pause, update in one commit:
  1. `.planning/STATE.md` — shifts the "current phase" marker + names the dispatch-ready brief path.
  2. `tasks/todo.md` — last-updated header reflects the pause.
  3. `tasks/codex-briefs/<next-pass>.md` — the runnable brief (exists already? check it's fresh and has enough detail per L-005/L-006).
  4. `tasks/lessons.md` — any lessons captured today.
- **Always** make the Codex brief self-contained: it must name its inputs (Stitch project ID, screen IDs, design-system ID, reference-file paths), its constraints, its acceptance criteria, its commit convention, and its exact first-step command. A future Codex reading it cold must be able to execute without asking a question.
- **Always** include an "Existing-code references" appendix in long briefs — tells Codex what's already in the repo so it doesn't reinvent route/compute split, RBAC, Zod validation, tenant middleware, test harness, etc.
- **Always** include per-component prop contracts (TypeScript interfaces) in the brief — Codex will use them verbatim.
- **Never** leave the next pass "implied" in chat history — push it to a file in the repo.


## Trigger Pattern

User signalled "we are running out of the plan for the week" and requested a state save + Codex handoff.

## Mistake

Treating the end-of-budget moment as "I'll summarise what happened and the next agent figures it out". Codex and future Claude sessions don't read chat transcripts — they read the repo. Everything needs to be durable.

## Cost Analysis

- Not specified in source lesson.

## Evidence

- Origin: `strategix-servicedesk/tasks/lessons.md`

## Effectiveness

- Not specified in source lesson.

## Cross-Project History

- Not specified in source lesson.

## Related

- [[strategix-L-001]]
- [[strategix-L-023]]
