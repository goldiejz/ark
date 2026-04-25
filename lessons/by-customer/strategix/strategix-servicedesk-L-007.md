---
id: strategix-servicedesk-L-007
title: Codex companion sandbox persists across runs regardless of interactive CLI changes
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

- **Always** before dispatching a Codex background task that needs network or `.git` writes, verify the effective sandbox by inspecting the companion's config or by doing a trivial smoke-test (`codex-companion.mjs task --background --write "run 'pnpm add --dry-run lodash && git diff --stat'"`). If that smoke test hits ENOTFOUND or index.lock, the sandbox is still on regardless of what the interactive CLI does.
- **Always** when Codex's environment is known to block commits, pre-position everything so the Claude fallback is trivial: a complete, runnable brief; acceptance criteria Claude can re-run from its own shell; a clear commit split. That way the sandbox hit adds ~10 minutes of Claude-side commit work, not a full re-run.
- **Always** capture any scope deviations the Codex run flagged (e.g. "TanStack/Zod could not be installed, used local primitives") as explicit Phase 1.5 backlog items in `tasks/todo.md` — don't let them hide inside a DEV.md footnote.
- **Never** repeat the same `codex-companion.mjs task` invocation after an environmental block; try `codex exec` directly with explicit `--sandbox` / `--ask-for-approval` flags, OR escalate to Claude-executes-the-brief with the Codex-produced artifacts already present.


## Trigger Pattern

User disabled Codex sandboxing interactively ("ive turned off sandboxing in codex for future") between Passes 1B and 1C. On Pass 1C dispatch via the companion (`task-moa1yojs-aingtw`), Codex still reported the identical blockers: `getaddrinfo ENOTFOUND registry.npmjs.org`, `.git/index.lock: Operation not permitted`, `EPERM 0.0.0.0:9229`. The user's change affected the interactive `codex` TUI but not the companion script's default sandbox policy used by `codex-companion.mjs task --background`.

## Mistake

Treating "I turned sandboxing off in Codex" as a blanket statement that applies to every Codex invocation path. The interactive CLI (`codex`) and the companion-script background runner have separate sandbox configurations, and a change in one does not necessarily propagate to the other. Assuming propagation and then being surprised when Pass 1C repeats Pass 1B's symptoms is an L-006 recurrence.

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
