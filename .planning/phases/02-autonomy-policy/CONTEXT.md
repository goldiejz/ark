# Phase 2 — AOS: Delivery Autonomy — Context

## Why this phase exists

Ark's original mandate: **user describes intent, Ark ships without further input**. Phase 1 fixed GSD shape detection but each delivery-path script still bubbles routine resource decisions to the user:

- Budget BLACK → "ask user to reset"
- Codex/Gemini quota exhausted → "ask user to fall back"
- 0 actionable tasks found → "ask user how to proceed"
- Phase-dir collision → "ask user which dir"

Every one of these has all the data needed to decide autonomously but lacks a policy engine to do so. **Manual gates in an autonomous system are bugs.** This phase is the AOS transition for the delivery layer.

## Position in AOS roadmap

This is Phase 2 of a 6-phase AOS journey (see ROADMAP.md). Each subsequent phase removes another class of manual gate:
- Phase 2 (this): delivery autonomy — `ark deliver` runs hands-off
- Phase 3: self-improving self-heal — observer learns which patterns fix tasks
- Phase 4: bootstrap autonomy — `ark create` runs hands-off
- Phase 5: portfolio autonomy — Ark picks which project to ship next
- Phase 6: cross-customer learning autonomy — lessons auto-promote to universal
- Phase 7: continuous operation — cron-driven, intent-from-INBOX

Phase 2 must lay the foundation (central policy engine, escalation queue, audit log, observer learning hook) that subsequent phases extend, NOT just fix the immediate symptom.

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

## User-confirmed architectural decisions

These were grilled out via AskUserQuestion before planning:

### 1. Scope boundary
- **Phase 2 = delivery only.** Bootstrap, portfolio, cross-customer are later phases.
- BUT: ROADMAP.md must spec all AOS phases (2–7) before executing Phase 2 — so we know we're heading somewhere coherent. (Done in ROADMAP.md.)

### 2. Policy configurability
- **Cascading from day 1:** `<project>/.planning/policy.yml` > `~/vaults/ark/policy.yml` > defaults in `ark-policy.sh`
- Env-var overrides for testing (`ARK_FORCE_QUOTA_CODEX`, `ARK_MONTHLY_ESCALATE_PCT`, etc.)
- Cascading resolver lives in `ark-policy.sh::policy_load_config()`

### 3. Escalation channel
- **Async queue file:** `~/vaults/ark/ESCALATIONS.md`
- True blockers append a section; that one phase halts but other autonomous work continues
- User reviews on next session start (or via `ark escalations` command)
- Phase 2 implements queue write only; consumption (Phase 7) is later

### 4. Self-heal definition
- **Layered + observer-learning:**
  - 1st retry: same dispatcher, prompt enriched with error blob + lessons.md + related code
  - 2nd retry: model escalate (Codex → Gemini → Haiku-API → Claude session)
  - 3rd retry: escalate to ESCALATIONS.md (true blocker)
  - **Observer hook:** every retry tagged with outcome. Phase 3 will read this to auto-improve self-heal patterns. Phase 2 only writes the data; Phase 3 builds the learner.

## Escalation policy (when user IS prompted)

Only these 4 classes reach the escalation queue:
1. **Monthly budget exceeded** (>= 95% of monthly cap, configurable)
2. **Architectural ambiguity** (multiple valid approaches with no policy preference)
3. **Destructive ops** (git push --force, dropping data, production deploy)
4. **Repeated self-heal failure** (3+ retries on same task)

Everything else: policy decides, decision is audit-logged, work proceeds.

## Constraints

- No breaking changes to Tier 1–7 verify (Tier 7 must stay 14/14)
- Backward compat: scripts run standalone if policy lib not sourced (graceful degradation)
- Observer must catch future regressions (`manual-gate-hit` pattern fires on any `read -p` in delivery-path scripts)
- Phase 2 lays observer-readable audit trail (`policy-decisions.jsonl`) for Phase 3 to consume

## Acceptance criteria (Phase 2 exit)

1. `ark deliver --phase 1.5` against strategix-servicedesk runs to completion (or hits one of the 4 escalation classes) with **zero stdin reads** and `ARK_FORCE_QUOTA_CODEX=true ARK_FORCE_QUOTA_GEMINI=true` set
2. `ark-policy.sh` exists with cascading config loader; ark-deliver/ark-team/execute-phase/ark-budget delegate routing to it
3. `ESCALATIONS.md` queue created on first true blocker; `ark escalations` command lists pending items
4. `policy-decisions.jsonl` audit log written for every policy call (input → decision → reason)
5. Tier 8 verify: simulated quota+budget exhaustion conditions; pipeline proceeds without input; existing Tier 1–7 still pass
6. Observer pattern `manual-gate-hit` catches `read -[pr]` in delivery-path scripts
7. `STRUCTURE.md` documents the AOS escalation contract and audit log format

## Out of scope (deferred to later AOS phases)

- Self-heal pattern learning (Phase 3)
- Bootstrap policy engine (Phase 4)
- Portfolio decision engine (Phase 5)
- Cross-customer lesson promotion (Phase 6)
- Continuous-operation cron daemon + INBOX consumption (Phase 7)
- Adjusting budget limit values themselves
- Multi-user authorization
