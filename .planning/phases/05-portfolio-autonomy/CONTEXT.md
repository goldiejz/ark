# Phase 5 — AOS: Portfolio Autonomy — Context

## Why this phase exists

Phases 2–4 made *individual project work* autonomous:
- Phase 2: delivery prompt-free
- Phase 3: delivery learns from outcomes
- Phase 4: project creation prompt-free

Phase 5 raises the lens to the **portfolio level**. Today, when you say "ship something," Ark needs you to specify which project. That's a manual gate. Phase 5 removes it.

`ark deliver` (with no `--phase`, no project name) should pick the highest-leverage project from the portfolio and run its next phase autonomously, audit-logged, with cross-project budget routing.

## Position in AOS roadmap

Phase 5 of the 6-phase journey. After this:
- Phase 6: Cross-customer learning autonomy (lessons promote across customers)
- Phase 7: Continuous operation (cron-driven INBOX consumption)

Phase 5 is the layer that lets Phase 7 actually choose work without you. Without portfolio decisions, the cron daemon would have nothing to pick.

## Architectural decisions (autonomous defaults)

### 1. Portfolio scope — Customer-tagged projects + scratch
- Discovers projects by walking `~/code/*` (or `$ARK_PORTFOLIO_ROOT` override)
- A project is a directory with `.planning/STATE.md` (Phase 4 contract)
- Customer is read from `<project>/.planning/policy.yml::bootstrap.customer` or path slug
- "scratch" projects (no customer tag) are deprioritized but eligible

### 2. Priority signals — Heuristic from project state
For each candidate project, compute a priority score from:
- **Phase health** — read `.planning/STATE.md` for current phase + status. Stuck phase (status=blocked or last-activity > 7d) → priority bump.
- **Test/verification health** — most recent verify report's pass count. Falling pass count → priority bump.
- **Customer monthly budget headroom** — pull from `~/vaults/ark/customers/<customer>/policy.yml::budget.monthly_used` and `monthly_cap`. Customer over 80% → DEFER (don't burn more on them).
- **CEO directives** — read `~/vaults/StrategixMSPDocs/programme.md` for explicit "next priority" lines. Explicit signal trumps heuristic.

Score formula: `priority = stuckness * 3 + falling_health * 2 + (monthly_headroom > 20 ? 1 : 0) + ceo_priority * 5`.

### 3. Cross-project budget routing
- Per-customer monthly cap defaults to 100K tokens (configurable)
- When a customer hits 80%, their projects DEFER until next budget window
- Ark won't burn 100% of monthly budget on one customer (cap = `(monthly_cap_total - already_used) / num_active_customers`)
- Verified via `_policy_log "portfolio" "DEFERRED" ...` audit trail

### 4. Decision audit
- Every portfolio decision logged via `_policy_log "portfolio" "<DECISION>" ...`
- Decisions: `SELECTED`, `DEFERRED_BUDGET`, `DEFERRED_HEALTHY`, `NO_CANDIDATE_AVAILABLE`
- Phase 6 reads these to learn portfolio patterns (does priority X correlate with delivery success?)

### 5. Default behavior — Conservative
- If only 1 candidate → run it (no priority needed)
- If 0 candidates → escalate `architectural-ambiguity` (no portfolio to work on; user must add one)
- If 2+ candidates with tied priority → pick most-recently-touched (least drift risk)
- If a higher-priority project exists but its budget is tapped → log DEFERRED, pick second

## Acceptance criteria (Phase 5 exit)

1. `scripts/ark-portfolio-decide.sh` exists; sourceable; self-test passes
2. `ark deliver` (no args) picks the highest-priority project from the portfolio with zero prompts
3. Decision audit-logged via `_policy_log "portfolio" "SELECTED" ...` with full priority breakdown in context
4. Per-customer monthly budget caps in `~/vaults/ark/customers/*/policy.yml` honored; over-cap customers' projects DEFERRED
5. CEO directive override: explicit priority in programme.md beats heuristic
6. Existing `ark deliver --phase N` (single project, current dir) unchanged (backward compat)
7. Tier 11 verify: synthetic 3-project portfolio across 2 customers, varying priority signals → asserts decision matches expected
8. Existing Tier 1–10 still pass

## Constraints

- Bash 3 compat (macOS)
- Single writer for audit log (`_policy_log` only)
- No new `read -p` in delivery-path scripts
- Backward compat: `ark deliver --phase N` from inside a project still works as before
- Portfolio root configurable via `$ARK_PORTFOLIO_ROOT` env (default `~/code`)
- Customer policy.yml is the source of truth for monthly budget state — Phase 5 reads, doesn't write the cap (writers are the project-level budget systems already)

## Out of scope

- Multi-machine portfolio sync (single laptop scope)
- ML-based priority (pure heuristic)
- Automatic project creation (Phase 4's job)
- INBOX consumption (Phase 7's job)
- Detailed cost projection / forecasting

## Risks

1. **Stuck-phase detection drives bad selections** — a phase blocked on user input gets repeatedly selected. Mitigated by: stuck phases that previously DEFERRED for the same reason → cooled off (24h backoff). Implemented as a check against `class:portfolio decision:DEFERRED` audit history.

2. **CEO directive parsing fragile** — programme.md is markdown; parser uses simple regex (`## Next Priority` heading). Mitigated by fallback to heuristic if directive not found.

3. **Customer attribution missing** — projects without `bootstrap.customer` get bucketed as "scratch". Acceptable; scratch is deprioritized.
