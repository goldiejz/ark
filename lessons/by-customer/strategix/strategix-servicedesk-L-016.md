---
id: strategix-servicedesk-L-016
title: `/codex:rescue` is read-only by design; use `codex exec` via Bash for writable implementation
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

- **Always** use `/codex:rescue` for: adversarial review, diagnosis, "tell me what's wrong here", post-implementation critique, or a cheap second-opinion patch proposal before the main implementation starts. Output is a read-only patch suggestion + findings.
- **Always** use foreground `codex exec "<prompt>"` via Bash (per L-014) for: writable implementation passes, schema + migration + tests + commit. The writable sandbox here comes from the user's `~/.codex/config.toml` `sandbox_mode = "danger-full-access"` posture, not from the rescue skill.
- **Always** treat the rescue turn's findings as pre-implementation intelligence. If the rescue finds drift between brief and reality (as here, §5 assumed `ticket_id NOT NULL` but reality is 3 nullable FKs + 3-way CHECK), amend the brief in the same turn before dispatching `codex exec`. Do not let the implementation turn re-discover the drift on its own — it will either blindly follow the wrong brief, or stall.
- **Never** invoke `/codex:rescue` expecting it to write + commit. If the task requires durable edits, pick the writable path from the start.
- **Never** conflate "the user said use this skill" with "this skill can actually do the task". If the skill hits a structural block (read-only sandbox, missing permission, wrong tier), fall back to the working path and capture the fallback as a lesson — don't repeat the same failing invocation.


## Trigger Pattern

Autonomous dispatch of the Phase 2 schema brief via the `codex:rescue` skill returned: `filesystem sandbox: read-only`, `approval policy: never`, and an explicit `apply_patch` rejection: "writing is blocked by read-only sandbox". The skill read the brief, read the schema, and flagged a real drift in brief §5 — but could not write a single line of code or run a single test. User's prior instruction ("use codex:rescue instead of bash to call codex") was correct for investigation-class work (the rescue subagent's stated purpose per its skill description: "Delegate investigation, an explicit fix request, or follow-up rescue work") but does not extend to primary implementation passes. L-014 governs the writable path; L-016 explains why the rescue skill is not a drop-in substitute.

## Mistake

Treating "skill named `rescue`" as "fix-and-commit". The rescue subagent's value is a second opinion and a proposed patch, not a durable file edit. Dispatching multi-table schema work through it wastes a turn on a read-only pass and a follow-up user correction. Worse: the rescue turn's findings (like the §5 drift here) may be more valuable than the edits it couldn't make — but without a writable fallback ready, that value is latent, not captured.

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
