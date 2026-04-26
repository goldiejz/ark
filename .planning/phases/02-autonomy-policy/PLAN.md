# Phase 2 — Autonomy Policy Layer (AOS Transition)

**Phase:** 02-autonomy-policy
**Status:** in-progress
**Owner:** ark autonomous (no user prompts for routine decisions)

## Goal

Transition Ark from "tool collection that asks" to **Autonomous Operating System (AOS)** that decides. User describes intent; Ark ships. User is only contacted for true blockers, not routine resource decisions.

## Acceptance Criteria

1. ✅ `ark deliver --phase 1.5` against strategix-servicedesk runs to completion or hits a real blocker — **never a routine resource gate** — with **zero user prompts**
2. ✅ `ark-policy.sh` exists as central decision module; ark-deliver/ark-team/execute-phase delegate routing to it
3. ✅ Tier 8 verify: simulated quota+budget exhaustion conditions; pipeline proceeds without input
4. ✅ Observer catches regressions: `manual-gate-hit` pattern fires when any script halts asking
5. ✅ Existing Tier 1–7 still pass (14/14 Tier 7 retained)
6. ✅ Escalation policy documented and enforced — only 4 true-blocker classes reach user

## Implementation Tasks

### Task 1: Create ark-policy.sh decision module
- [ ] New file `scripts/ark-policy.sh`
- [ ] Functions:
  - `policy_budget_decision()` — args: phase_tokens_used, phase_cap, monthly_used, monthly_cap → emits: AUTO_RESET / ESCALATE_MONTHLY_CAP / PROCEED
  - `policy_dispatcher_route()` — args: task complexity, current budget tier → emits: codex / gemini / haiku-api / claude-session / regex-fallback (no prompts)
  - `policy_zero_tasks()` — args: phase_dir, plan_count → emits: SKIP_LOGGED / ESCALATE_AMBIGUOUS
  - `policy_dispatch_failure()` — args: error_blob, retry_count → emits: RETRY_NEXT_TIER / SELF_HEAL / ESCALATE_REPEATED
  - `policy_audit()` — every decision writes to `observability/policy-decisions.jsonl` with reasoning
- [ ] Self-test block (sourced with `test`) covering each function

### Task 2: Wire ark-budget.sh to policy on BLACK
- [ ] Replace "ask user to reset" branch with `policy_budget_decision()` call
- [ ] If policy returns AUTO_RESET → reset phase counter, log decision, continue
- [ ] If policy returns ESCALATE_MONTHLY_CAP → halt with explicit user message (real blocker)
- [ ] Add `--policy-only` flag for dry-runs (returns decision without acting)

### Task 3: Wire execute-phase.sh to policy on dispatch
- [ ] Replace cascading `command -v` checks with `policy_dispatcher_route()` call
- [ ] If active Claude session detected and external CLIs throttled → policy returns claude-session, not user prompt
- [ ] If regex-fallback the only option → log + emit handoff file, exit 2 (already wired)

### Task 4: Wire ark-deliver.sh on zero-task phases
- [ ] Replace "Phase has 0 actionable tasks — auto-skipping" warn with `policy_zero_tasks()`
- [ ] Policy logs the skip reason and continues to next phase
- [ ] Only escalate if **all** phases in roadmap report zero (true ambiguity)

### Task 5: Wire ark-team.sh on dispatch failure
- [ ] Replace any halt-on-quota-error branches with `policy_dispatch_failure()`
- [ ] Self-heal triggered automatically per policy, not per ad-hoc script branch
- [ ] After 3 retries with self-heal, escalate (only after exhaustion)

### Task 6: Strip remaining "ask user" branches
- [ ] Audit: `grep -rEn 'read -[pr]|read.*PROMPT|read.*"[\"$]?[YyNn]' scripts/` — find every interactive read
- [ ] For each: convert to policy call OR confirm it's a true blocker (destructive op, monthly cap)
- [ ] Document remaining intentional prompts in `STRUCTURE.md` (escalation contract)

### Task 7: Tier 8 verify — autonomy assertions
- [ ] Add Tier 8 to `ark-verify.sh`: "Autonomy under stress"
- [ ] Tests:
  - `policy_budget_decision` auto-resets when monthly < 80%
  - `policy_budget_decision` escalates when monthly > 95%
  - `policy_dispatcher_route` returns claude-session when both Codex + Gemini env-vars set to "throttled"
  - `policy_zero_tasks` skips and logs when phase has empty plans
  - End-to-end: simulate `ark deliver` with all CLIs throttled + phase BLACK → verify session-handoff emitted, no `read` calls hit
- [ ] Pre-flight: `grep -c "read -" scripts/*.sh` returns 0 in dispatch-path scripts (only allowed in setup/init scripts)

### Task 8: Observer pattern — manual-gate-hit
- [ ] Add to `observability/observer/patterns.json`:
  - regex: `(read -[pr]|press any key|continue\?|y/N)` in delivery logs
  - severity: critical
  - lesson_after_n: 1
  - description: "An autonomous-path script hit an interactive prompt — autonomy regression"
- [ ] Tail target: `.planning/delivery-logs/*.log` and dispatch logs

### Task 9: Document AOS escalation contract
- [ ] Update `STRUCTURE.md` with an "AOS Escalation Contract" section
- [ ] Enumerate the 4 true-blocker classes (monthly cap, architectural ambiguity, destructive ops, repeated failure)
- [ ] Document `policy-decisions.jsonl` format and how to audit Ark's autonomous choices
- [ ] Update `~/.claude/skills/ark/SKILL.md` to declare AOS posture

### Task 10: End-to-end success-signal run
- [ ] Force-throttle external CLIs (env var stubs)
- [ ] Run `ark deliver --phase 1.5` on strategix-servicedesk
- [ ] Verify: zero `read` blocks hit, decisions logged, session-handoff emitted, observer silent
- [ ] If a real blocker hits → confirm it's in the 4 escalation classes, not a routine gate

## Verification Strategy

After each task: `bash scripts/ark-verify.sh --tier 8` (will fail until Task 7).
After Task 7: full suite must show 14/14 Tier 7 + new Tier 8 all pass.
After Task 10: end-to-end run produces a `policy-decisions.jsonl` with at least one entry of each class observed (auto-reset, route, skip), zero entries of class "user-prompted-routine".

## Risks

1. **Stripping `read` calls breaks legitimate setup flows** — mitigated by limiting policy to dispatch-path scripts; init/repair scripts may keep prompts
2. **Auto-reset abuse drains monthly budget faster** — mitigated by 95% monthly threshold escalation
3. **Self-heal loops** — mitigated by 3-retry cap + escalate

## Dependencies

- Phase 1 complete (gsd-shape lib, multi-plan support) — confirmed
- Observer daemon running — confirmed
- ark-context.sh runtime detection — confirmed

## Out of Scope

- Cross-project policy coordination
- Adjusting budget limits themselves
- Multi-user authorization layers

## Success Signal

```bash
# Force both external CLIs to "throttled" state
export ARK_FORCE_QUOTA_CODEX=true
export ARK_FORCE_QUOTA_GEMINI=true
cd ~/code/strategix-servicedesk
ark deliver --phase 1.5
```

Expected: pipeline runs to completion (or session-handoff for engineer role), produces full team artifacts, never blocks on `read`. `cat ~/vaults/ark/observability/policy-decisions.jsonl` shows the audit trail of decisions Ark made on your behalf.

If this works, Ark is officially AOS.
