---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
current_phase: "Phase 3 (AOS: Self-Improving Self-Heal)"
status: complete
last_updated: "2026-04-26T15:30:00Z"
progress:
  total_phases: 4
  completed_phases: 3
  total_plans: 26
  completed_plans: 25
  percent: 96
---

# Ark — Implementation State

**Last updated:** 2026-04-26T15:30:00Z
**Current Phase:** Phase 3 (AOS: Self-Improving Self-Heal)
**Status:** complete

## Phase 0 — Bootstrap (complete)

- [x] Vault structure established (lessons/, cache/, observability/, scripts/, hooks/, employees/, dashboard/)
- [x] 24 CLI commands wired into `ark`
- [x] 14 employees in registry
- [x] Hooks installed (SessionStart, Stop)
- [x] Skill /ark registered in Claude Code
- [x] GitHub repo: goldiejz/ark
- [x] Brain → Ark rename complete
- [x] ark verify suite (36/36 pass)
- [x] Continuous observer daemon running
- [x] Production safety gate verified

## Phase 1 — GSD Integration (in-progress)

See `.planning/phases/01-gsd-integration/PLAN.md`

Goal: Make Ark fully aware of GSD's planning structure so `ark deliver` works correctly on GSD projects.

## Phase 2 — AOS: Delivery Autonomy (complete)

See `.planning/phases/02-autonomy-policy/`

**Goal:** Ark decides routine resource questions autonomously; only 4 true-blocker classes reach the user via `~/vaults/ark/ESCALATIONS.md`.

**Exit gate:** Tier 8 25/25 + Tier 1–7 14/14 retained (`scripts/ark-verify.sh`).

| Plan | Outcome |
|------|---------|
| 02-01 | `scripts/ark-policy.sh` foundation: cascading config loader, decision functions, audit log with 64-bit `decision_id` (16-hex from `/dev/urandom`), `outcome`/`correlation_id` Phase-3-ready fields |
| 02-02 | `~/vaults/ark/ESCALATIONS.md` queue + `ark escalations` (list/show/resolve) command |
| 02-03 | `scripts/ark-budget.sh` BLACK halt replaced with `policy_budget_decision` delegation |
| 02-04 | `scripts/execute-phase.sh` dispatch routing via `policy_dispatcher_route`; session-handoff sentinel cost recorded (observable BEFORE/AFTER delta) |
| 02-05 | `scripts/ark-deliver.sh` zero-task and phase-collision paths delegate to policy |
| 02-06 | `scripts/ark-team.sh` in-process retry loop (4 dispatches max); post-loop `ark_escalate` always-fire; `execute-phase.sh::dispatch_task` invokes `self-heal.sh --retry` |
| 02-06b | `scripts/self-heal.sh` refactored to layered 3-retry contract (enriched → model-escalate → queue); audit via single `_policy_log` writer |
| 02-07 | Remaining `read -p` calls stripped or tagged `# AOS: intentional gate`; observer pattern `manual-gate-hit` shipped |
| 02-08 | Tier 8 verify suite (autonomy under stress): isolated dedup test, schema integrity, entropy stress, dispatcher-route assertions |
| 02-09 | STRUCTURE.md AOS Escalation Contract; REQ-AOS-01..07 minted; STATE.md updated |

## Phase 3 — AOS: Self-Improving Self-Heal (complete)

See `.planning/phases/03-self-improving-self-heal/`

**Goal:** Audit log → outcome tagger → pattern learner → auto-patch policy.yml under file-lock + git commit + audit entry. Self-improving without losing the schema lock or the true-blocker contract.

**Exit gate:** Tier 9 20/20 + Tier 1–8 retained — confirmed `bash scripts/ark-verify.sh --tier 7` 14/14, `--tier 8` 25/25, `--tier 9` 20/20 (after `execute-phase.sh` restored from `.HALTED` snapshot in 03-08).

**Substrate note:** Phase 2.5 migrated the audit log to SQLite at `~/vaults/ark/observability/policy.db` (schema preserved, `schema_version=1`). Phase 3 reads + patches via `sqlite3`; synthetic fixtures use `INSERT INTO decisions`. See `.planning/phases/03-self-improving-self-heal/SUPERSEDES.md`.

| Plan | Outcome |
|------|---------|
| 03-01 | `scripts/lib/outcome-tagger.sh`: SINGLE writer for `outcome` column; idempotent SQL UPDATE; window-configurable inference (success/failure/ambiguous) |
| 03-02 | `scripts/policy-learner.sh`: pattern scoring by `(class, decision, dispatcher, complexity)` via SQL GROUP BY; 5/80%/20% thresholds; true-blocker filter (`class NOT IN ('escalation','self_improve')`) |
| 03-03 | `learner_apply_pending`: mkdir-lock + python3/PyYAML atomic patch + vault git commit + `_policy_log self_improve PROMOTED|DEPRECATED` audit |
| 03-04 | `scripts/lib/policy-digest.sh::learner_write_digest`: `~/vaults/ark/observability/policy-evolution.md` with Promoted, Deprecated, Mediocre sections; idempotent |
| 03-05 | `scripts/ark-deliver.sh::run_phase` post-phase trigger (after `update_state`, non-fatal, windowed `--since` 1h-ago, output to `.planning/delivery-logs/learner-phase-N.log`); restored ark-deliver.sh from `.HALTED` snapshot |
| 03-06 | `ark learn` subcommand (default last-7-days, `--full`, `--since DATE`, `--tag-first`) |
| 03-07 | Tier 9 verify suite (synthetic SQLite fixture, isolated tmp vault, 20 checks; mirrors Phase 2 NEW-W-1 isolation; md5 guarantee on real vault DB) |
| 03-08 | STRUCTURE.md AOS Self-Improving Self-Heal Contract; REQ-AOS-08..14 minted; STATE.md Phase 3 close; SKILL.md updated; `scripts/execute-phase.sh` restored from `.HALTED` (closes T7+T8 source-count regression) |

## Phase 4+ — Future

Next per `.planning/ROADMAP.md`: **Phase 4 — Bootstrap autonomy** (`ark create` runs hands-off; bootstrap-decision learning feeds the same audit log).
