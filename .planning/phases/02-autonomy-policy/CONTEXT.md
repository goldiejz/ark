# Phase 2 — Autonomy Policy: Context

## Why this phase exists

Ark's original mandate (from Day 1): **user describes intent, Ark ships without further input**. Phase 1 fixed GSD shape detection but each script still bubbles routine resource decisions back to the user:

- Budget BLACK → "ask user to reset"
- Codex/Gemini quota exhausted → "ask user to fall back"
- 0 actionable tasks found → "ask user how to proceed"
- Phase-dir collision → "ask user which dir"

Every one of these has all the data needed to decide autonomously. They lack a policy engine to do so. **Manual gates in an autonomous system are bugs.**

## Symptoms observed

Running `ark deliver --phase 1.5` on strategix-servicedesk after Phase 1 fix:
- Plans 01–04 shipped via active Claude session (autonomy worked)
- Phase budget hit BLACK at 66.7K/50K phase cap
- Pipeline halted, asked user to run `ark budget --reset`
- Monthly cap was at 6.7% (1M cap, plenty of headroom) — no real cost reason to halt
- Active Claude session was detected — execute-phase already had session-handoff path
- All data needed to auto-route was present; nothing wired the policy

## Root cause

Phase 1 verified scripts work correctly (Tier 1–7). Phase 1 did not verify *the system makes autonomous decisions*. Acceptance criteria checked "ark deliver finds 51 tasks" — never "ark deliver runs to completion without user input."

## Decision

Build a central policy engine (`ark-policy.sh`) and route all routine decisions through it. Strip "ask user" branches from individual scripts. Add Tier 8 verification that simulates resource exhaustion and asserts no-prompt completion.

## Escalation policy (when user IS prompted)

Only true blockers escalate:
1. **Monthly budget exceeded** (1M tokens/month default) — real cost ceiling
2. **Architectural ambiguity** — multiple valid approaches with no policy preference
3. **Destructive ops** — git push --force, dropping data, production deploy
4. **Repeated self-heal failure** — same task fails 3+ times after fix attempts

Everything else: decide and log.

## Constraints

- No breaking changes to Tier 1–7 verify (must stay 14/14 on Tier 7)
- Backward compat: scripts run standalone work without the policy engine sourced
- Observer must catch future regressions (`manual-gate-hit` pattern)

## Out of scope

- Changing budget limits themselves (separate concern)
- Cross-project policy (per-project state remains separate)
- Multi-user authorization (single-user system)
