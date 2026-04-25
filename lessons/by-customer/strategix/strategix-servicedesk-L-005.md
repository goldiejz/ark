---
id: strategix-servicedesk-L-005
title: Codex background tasks may produce files without committing them
date_captured: 2026-04-22
origin_project: strategix-servicedesk
origin_repo: servicedesk
scope: ["process", "delivery"]
severity: HIGH
applies_to_domains: ["*"]
customer_affected: [strategix]
universal: true
---

## Rule

- **Always** verify post-run that Codex made the expected commits: run `git log --oneline <base-head>..HEAD` and `git status --short` after the task terminates. A clean tree with new HEAD is the required terminal state; a dirty tree with `completed` status is a silent half-finish.
- **Always** when the working tree is dirty after a `completed` Codex task: Claude reads the produced files, runs the acceptance criteria itself, and commits the work in scoped conventional commits. Do not re-dispatch Codex just to commit — the files are right; the commit discipline is Claude's fallback.
- **Never** rely on Codex's `--background` mode to report a final assistant summary back to the companion — `touchedFiles` and `assistantMessage` are often empty for backgrounded runs even when substantial changes exist in the working tree.
- **Always** structure the Codex brief's acceptance criteria so they are runnable by Claude post-hoc (`pnpm test`, `pnpm typecheck`, `wrangler d1 execute`, `curl /health`) — that way the "Codex didn't commit" case doesn't block verification.


## Trigger Pattern

Pass 1A scaffold handoff (`task-mo9zk9yl-vsux84`, gpt-5.4, effort high, background). Codex ran 12m 17s, produced 17 new files + 2 modifications, **hit the `completed` terminal state without making a single git commit**. The brief explicitly asked for 8 conventional commits with a suggested sequence. `touchedFiles: []` in the companion result output despite the working tree being dirty with real content. The acceptance-criteria self-checks Codex ran left no audit trail because they weren't recorded in a commit.

## Mistake

Trusting Codex's `completed` status as "work is durable and attributed". A Codex background task can end having written correct files to the working tree but never having staged, committed, or pushed them — especially when the prompt asks for commits but Codex treats commit as an optional epilogue rather than a required gate.

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
