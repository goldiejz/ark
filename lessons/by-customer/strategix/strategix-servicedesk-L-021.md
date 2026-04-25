---
id: strategix-servicedesk-L-021
title: Reviewer artefacts must cite existing rules verbatim, not paraphrase or extrapolate
date_captured: 2026-04-24
origin_project: strategix-servicedesk
origin_repo: servicedesk
scope: ["process", "delivery"]
severity: HIGH
applies_to_domains: ["*"]
customer_affected: [strategix]
universal: true
---

## Rule

- **Always** when authoring a reviewer or brief-writer, quote the authoritative rule **verbatim** from its source (`CLAUDE.md §<section>`, `tasks/lessons.md L-NNN`, the actual lint script in `package.json`) rather than paraphrasing. Copy the exact sentence; cite the section. A reviewer that doesn't cite cannot be audited.
- **Always** distinguish between rules that share surface area. The signature "never deleted" rule and the tickets/time_entries/timesheets "soft-delete via `deleted_at`" rule look similar and act opposite. Spell out both with their sources in the reviewer, not one merged rule.
- **Always** before writing any check that depends on post-hoc author attribution (Codex vs Claude, bot vs human, CI vs local), verify the git-log actually distinguishes them. If global attribution is disabled (`~/.claude/settings.json` typically does this), author-trailer checks return a false signal for every commit. Use dispatch-time enforcement instead.
- **Always** before writing acceptance criteria or "reuse these helpers" sections for a brief, re-read the actual exports from the file. `grep "^export" src/lib/<file>.ts` or read the file — do not name helpers from memory. Name drift between "what the brief says to import" and "what the file actually exports" costs a Codex round.
- **Always** before writing a reviewer check that references `.planning/*.md` or `tasks/*.md` state, read the current state of those files. `tasks/todo.md` or `.planning/STATE.md` may be in a mode (e.g. "Claude-implements for Phase 1") that makes a generic rule temporarily wrong.
- **Never** invent requirements that the authoritative source does not state. "`tenant_id` indexed" or "audit columns NOT NULL" sounded like good practice, but they're not in `CLAUDE.md §Architecture Conventions`. A reviewer that enforces undocumented preferences as rules generates false positives and drags future work off-pattern.
- **Never** merge two rules with similar vocabulary into one. Soft-delete (tickets) and never-delete (signatures) are distinct rules with opposite allowed behaviours. The temptation to compress is the source of the contradiction.


## Trigger Pattern

Wrote four `.claude/agents/*.md` review agents in one pass. Codex stop-hook flagged the set for "contradictory repo rules and false review results" before commit. On inspection, the agents had paraphrased `CLAUDE.md §Architecture Conventions` in ways that invented requirements or inverted them: asserted `tenant_id` must be "indexed" (not a CLAUDE.md rule), asserted audit columns must be "NOT NULL" with specific types (CLAUDE.md just says "carries"), conflated signature artifacts (never deleted, hard OR soft) with the tickets/time_entries/timesheets rule (soft-delete via `deleted_at` IS the allowed path), tried to enforce the L-001 planning/coding split by inspecting commit author trailers (impossible — global attribution is disabled, so every commit shows the same git identity), and ignored that `tasks/todo.md` currently locks "Claude-implements (not Codex)" for Phase 1 MVP per L-006/L-007, which would make the split-violation check fire on every legitimate Phase 1 commit. The agents also cited `requireRole` as a direct export of `src/lib/rbac.ts` when the actual export is `createRequireRole(deps)` factory, and invented event-bus function names (`emit`, `eventBus.publish`) when the actual export is `emitServiceDeskEvent`.

## Mistake

When authoring a reviewer (agent, slash command, CI rule), writing rules from memory or from a quick read of `CLAUDE.md` without re-reading the actual source files and the actual lint scripts. Reviewers that paraphrase rules tighten them, loosen them, or invent new ones — and because reviewers run against future diffs, the errors compound: every false positive erodes trust in the reviewer, and every false negative masks real defects. Pairing this with invented symbol names (`requireRole` instead of `createRequireRole`, `emit(` instead of `emitServiceDeskEvent`) means the reviewer also mis-teaches the thing it's supposed to enforce.

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
