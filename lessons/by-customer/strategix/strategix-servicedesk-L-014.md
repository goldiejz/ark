---
id: strategix-servicedesk-L-014
title: Claude dispatches Codex (and `claude`) directly via foreground Bash; never background, never push back to user without cause
date_captured: 2026-04-23
origin_project: strategix-servicedesk
origin_repo: servicedesk
scope: ["process", "delivery"]
severity: HIGH
applies_to_domains: ["*"]
customer_affected: [strategix]
universal: true
---

## Rule

- **Always** dispatch Codex via foreground `codex exec "<prompt>"` from Claude's own Bash tool. Same for nested `claude -p "<prompt>"` runs. Set `timeout: 600000` when the run might be long.
- **Always** when a brief's expected runtime exceeds Bash's 10-minute hard cap (e.g. 45–60 min), pick one of: (a) split the brief into shorter passes, (b) accept the timeout — Codex's commits land before exit so the work isn't lost, just unreported in this turn; Claude polls `git log` and `git status` to reconcile, (c) ask the user once whether to split or accept the timeout.
- **Never** invoke Codex with `run_in_background: true`, `--background`, `codex-companion task --background`, or any async/detached pattern. The user must be able to see what Codex is doing in the conversation transcript.
- **Never** default to "paste this into your terminal." Only hand dispatch back when (a) the user explicitly says "let me drive it", or (b) the user has asked to tune the prompt iteratively. "The run is long" is not a reason — see split/accept-timeout above.
- **Apply equally to `claude` invocations.** Claude calling `claude -p` for sub-tasks follows the same rule: foreground via Bash, never `run_in_background`, never push back to user.


## Trigger Pattern

User opened a Claude Code CLI session and asked Claude to pick up the Phase 2 schema work. Claude over-applied an earlier "never background Codex" feedback memory, treated it as "never invoke Codex from a Claude session", and handed the dispatch command back to the user's terminal twice. User corrected: "actually the brief should've stated you can run codex commands when required." Then again: "ok once again YOU can run claude and codex... I don't have to run it." The rule is "never background", not "never invoke". Foreground `codex exec` via Bash streams output back into the transcript, which is the visibility the original feedback wanted.

## Mistake

Conflating "don't run async/detached" with "don't run at all". Pushing dispatch back to the user when Claude has the tools to do it directly defeats the purpose of an orchestrator session — the user opened CLI specifically to avoid context-switching between terminals. Treating Bash's 10-minute timeout as a reason to abdicate is also wrong: Codex commits before exit, so a Bash timeout doesn't kill the work — Claude polls `git log` afterward to see what landed.

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
