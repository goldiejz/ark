---
id: strategix-servicedesk-L-006
title: Codex background dispatch can be environment-blocked; Claude fallback is legitimate
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

- **Always** read the Codex log file when a task terminates with `completed` but no commits and no touched files — the final assistant message almost always names the blocker. Companion `result --json` is misleading here (`touchedFiles: []` even when there was work).
- **Always** pre-install dependencies via Claude's Bash when a Codex brief depends on new packages — warm the pnpm store so sandbox-blocked network doesn't matter. This is a cheap one-liner that unblocks most adjacent Codex failures.
- **Always** when Codex is environment-blocked on a shippable pass, fall back to Claude-executes-the-brief. The brief itself is the durable artifact; who types the code is secondary. Commit as Claude, annotate in STATE.md that the pass was Claude-authored-and-committed, and capture the environmental reason in lessons.
- **Always** when the user flips Codex sandbox off for future runs, record it as a project fact (not a memory) so the next Codex dispatch actually takes advantage — don't keep defaulting to the old failure-prone config.
- **Never** invoke `--dangerously-bypass-approvals-and-sandbox` — it's explicitly prohibited by the user's global rules even when it would unblock a task.


## Trigger Pattern

Pass 1B dispatched to Codex (`task-moa0ewkl-4w8ovw`) terminated at 7m 1s with a completely empty tree and zero commits. Log inspection showed two hard blockers inside the Codex companion sandbox:
1. `getaddrinfo ENOTFOUND registry.npmjs.org` — outbound DNS blocked; `pnpm add better-auth` failed at the resolve step.
2. `fatal: Unable to create '.git/index.lock': Operation not permitted` — `.git` read-only in the sandbox, so `git add` / `git commit` cannot run.

These are properties of the Codex companion's default sandbox, not of this project. `--dangerously-bypass-approvals-and-sandbox` would address both but matches the user's security rule against unsafe-agent flags and was refused. Scoped `--full-auto` (workspace-write) is not wired through the companion's `task` subcommand, so it's not a one-line override either.

## Mistake

Treating a Codex `completed` status as "work landed" when the run was environmentally blocked. Retrying with the same configuration produces the same result. Likewise, trying to bypass the sandbox with a flag the user's own rules forbid is a waste of a retry slot.

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
