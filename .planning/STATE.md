---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
current_phase: "Phase 7 (AOS: Continuous Operation)"
status: complete
last_updated: "2026-04-26T21:15:00Z"
progress:
  total_phases: 10
  completed_phases: 8
  total_plans: 57
  completed_plans: 55
  percent: 96
---

# Ark — Implementation State

**Last updated:** 2026-04-26T21:15:00Z
**Current Phase:** Phase 7 (AOS: Continuous Operation)
**Status:** complete

## 🎉 AOS Journey Terminal (2026-04-26)

**Phase 7 closes the AOS journey.** All 8 AOS phases now complete: Phase 0 (Bootstrap) → Phase 2 (Delivery Autonomy) → Phase 2.5 (SQLite substrate) → Phase 3 (Self-Improving Self-Heal) → Phase 4 (Bootstrap Autonomy) → Phase 5 (Portfolio Autonomy) → Phase 6 (Cross-Customer Learning) → Phase 6.5 (CEO Dashboard) → Phase 7 (Continuous Operation).

Original ROADMAP.md North Star achieved: **user authors intent in markdown, walks away, returns to find projects shipped** (or true blockers escalated via async ESCALATIONS.md queue). The CEO loop is closed.

**Next phase pointer:** Phase 8 (Production Hardening + Reporting). Phase 8 is **OUTSIDE the AOS journey** — it is post-AOS productionization (multi-machine vault sync, disaster recovery drills, investor/customer report templates, stress-test under load), not autonomy. The autonomy contract is fixed at the close of Phase 7.

**Phase 8 backlog (carry-forward from Phase 7):**

- **Tier 8 baseline 24/25** — pre-existing failure on `ark escalations subcommand dispatches` test pattern; predates Phase 6.5; Phase 7 did not touch this scope. Phase 8 should investigate and restore to 25/25.
- **Unauthorized goldiejz/acme-sd repo** — leftover from Phase 4 Plan 04-04 first-smoke-test (unguarded `gh repo create` block; defect fixed in same plan via `ARK_CREATE_GITHUB` env gate, default off). User must manually delete via `gh repo delete goldiejz/acme-sd --yes` (after granting `delete_repo` scope) or GitHub web UI.
- **Phase 1 (GSD Integration) 3 of 10 ROADMAP items unchecked** — STRUCTURE.md GSD/Ark relationship doc, employees-registry gsd-planner/gsd-verifier additions, doc refresh. Lives outside AOS scope; can ship independently of Phase 8.

## Plan-count audit (2026-04-26, drift reconciliation, Phase 7 close)

Plan 06-03 ran a `gsd-tools` state recompute that overwrote 05-07's hand-set frontmatter values. 06-06 reconciled by counting disk truth. 06.5-07 re-reconciled after Phase 6.5 added 8 plans. 07-08 (this plan) reconciles after Phase 7 added 8 more plans (07-01..07-08), closing the AOS journey:

| Phase | PLAN.md files | SUMMARY.md files | Status |
|-------|--------------:|-----------------:|--------|
| Phase 0 — Bootstrap | 0 | 0 | complete (narrative; pre-`.planning/phases/`) |
| Phase 1 — GSD Integration | 1 (`PLAN.md`) | 0 | in-progress (3 of 10 ROADMAP items unchecked) |
| Phase 2 — Delivery Autonomy | 10 | 10 | complete |
| Phase 2.5 — SQLite backend | 1 (`PLAN.md`) | 0 | complete (substrate plan; outcome inlined in Phase 3 SUMMARY chain) |
| Phase 3 — Self-Improving Self-Heal | 8 | 8 | complete |
| Phase 4 — Bootstrap Autonomy | 8 | 8 | complete |
| Phase 5 — Portfolio Autonomy | 7 | 7 | complete |
| Phase 6 — Cross-Customer Learning | 6 | 6 | complete |
| Phase 6.5 — CEO Dashboard | 8 | 8 | complete |
| Phase 7 — Continuous Operation | 8 | 8 | complete (after this plan) |
| **Totals** | **57 PLAN.md** | **55 SUMMARY.md** | — |

Disk-counted via `for d in .planning/phases/*/; do ls "$d"*PLAN.md "$d"*SUMMARY.md 2>/dev/null | wc -l; done`. `total_plans: 57` reflects the 57 PLAN.md files on disk (49 prior + 8 from Phase 7: 07-01..08). `completed_plans: 55` reflects the 55 SUMMARY.md files (Phase 1 PLAN.md + Phase 2.5 PLAN.md remain SUMMARY-less; their narratives are folded into Phase 3+ closure docs). `total_phases: 10` enumerates Phases 0,1,2,2.5,3,4,5,6,6.5,7. `completed_phases: 8` counts Phases 0,2,2.5,3,4,5,6,6.5,7 marked complete in this file (Phase 1 remains in-progress and excluded; if Phase 1 closes, this count moves to 9 — but Phase 1 is outside the AOS journey, see "AOS Journey Terminal" header above).

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

## Phase 4 — AOS: Bootstrap Autonomy (complete)

See `.planning/phases/04-bootstrap-autonomy/`

**Goal:** `ark create "<one-line description>" --customer <name>` runs to completion with zero prompts. Inference engine + audit trail + atomic CLAUDE.md/policy.yml writes; backward-compat for flag-mode; production-side-effect gate around `gh repo create`.

**Exit gate:** Tier 10 22/22 + Tier 7/8/9 retained — confirmed `bash scripts/ark-verify.sh --tier 7` 14/14, `--tier 8` 25/25, `--tier 9` 20/20, `--tier 10` 22/22.

| Plan | Outcome |
|------|---------|
| 04-01 | `scripts/bootstrap-policy.sh`: keyword-overlap inference engine; `bootstrap_classify` orchestrator emitting TSV verdict + `_policy_log "bootstrap"` audit; confidence threshold escalates `architectural-ambiguity` to ESCALATIONS.md; bash 3 compat; 16-test self-test in isolated tmp vault |
| 04-02 | `bootstrap/project-types/*-template.md` frontmatter tagged with `keywords:`, `default_stack:`, `default_deploy:`; phrase-aware tokenizer; new `custom-template.md` empty-keyword catch-all; absolute-match scoring (matched × 20, capped 100) |
| 04-03 | `bootstrap/claude-md-template.md` base with named anchors + 4 `claude-md-addendum/<type>.md` files (service-desk, revops, ops-intelligence, custom); anchor-on-own-line discipline for sed `r`+`d` composition |
| 04-04 | `scripts/ark-create.sh` description-mode wired through `bootstrap_classify`; sed-pipeline + atomic mv for CLAUDE.md; auto-generated `.planning/policy.yml`; `_policy_log "bootstrap" RESOLVED_FINAL/FLAG_OVERRIDE` audit; `ARK_CREATE_GITHUB` env gate added (default off) after unguarded-`gh repo create` incident |
| 04-05 | `scripts/lib/bootstrap-customer.sh` mkdir-lock customer dir + idempotent seed; `scripts/lib/policy-config.sh` extended with customer layer (env > project > customer > vault > default) |
| 04-06 | `scripts/ark` dispatcher `cmd_create` pass-through to ark-create.sh; help text reflects description-mode + flag-mode + `ARK_CREATE_GITHUB` gate; no `read -p` regression |
| 04-07 | Tier 10 verify suite (5 fixtures × multi-assert + flag-mode + cascading-customer + low-confidence + isolation md5; 22 checks total); Tier 1-9 regression sweep clean |
| 04-08 | REQ-AOS-15..REQ-AOS-22 minted; STATE.md Phase 4 close; ROADMAP.md checkboxes; STRUCTURE.md AOS Bootstrap Autonomy Contract; SKILL.md Phase 4 posture |

**Known issue (out-of-scope manual cleanup):** During Plan 04-04's first smoke test, an unguarded `gh repo create` block in `ark-create.sh` created an unauthorized public repo at `https://github.com/goldiejz/acme-sd`. The defect was fixed in 04-04 (`ARK_CREATE_GITHUB` env gate, default off). The leftover repo could not be deleted by the agent (token lacked `delete_repo` scope). User must manually delete via `gh repo delete goldiejz/acme-sd --yes` (after granting `delete_repo` scope) or GitHub web UI. See `.planning/phases/04-bootstrap-autonomy/04-04-SUMMARY.md` "Production-side-effect incident (handled)".

## Phase 5 — AOS: Portfolio Autonomy (complete)

See `.planning/phases/05-portfolio-autonomy/`

**Goal:** `ark deliver` (no args) picks the highest-leverage project from the portfolio and runs its next phase, audit-logged, with cross-project budget routing and 24h cool-down.

**Exit gate:** Tier 11 16/16 + Tier 7/8/9/10 retained — confirmed `bash scripts/ark-verify.sh --tier 7` 14/14, `--tier 8` 25/25, `--tier 9` 20/20, `--tier 10` 22/22, `--tier 11` 16/16.

| Plan | Outcome |
|------|---------|
| 05-01 | `scripts/ark-portfolio-decide.sh` foundation: discovery + scoring + winner; sentinel sections; bash-3 self-test |
| 05-02 | `_portfolio_budget_headroom`: per-customer monthly cap reader via existing cascading config; 0 headroom signals DEFERRED_BUDGET |
| 05-03 | `_portfolio_ceo_priority`: programme.md `## Next Priority` parser; +5 weight when match |
| 05-04 | `_portfolio_recently_deferred` + full `portfolio_decide`: 4 decision classes (SELECTED/DEFERRED_BUDGET/DEFERRED_HEALTHY/NO_CANDIDATE_AVAILABLE) audit-logged via single-writer `_policy_log`; 24h cool-down via sqlite SELECT against `class:portfolio` history |
| 05-05 | `scripts/ark-deliver.sh` no-args portfolio routing branch; `scripts/ark` help text; backward compat for `--phase N` and in-project invocation |
| 05-06 | Tier 11 verify suite (synthetic 3-project / 2-customer fixture, 16 checks; isolated mktemp vault; real DB md5 invariant) |
| 05-07 | REQ-AOS-23..30 minted; STATE.md Phase 5 close; ROADMAP.md checkboxes; STRUCTURE.md AOS Portfolio Autonomy Contract; SKILL.md Phase 5 posture |

## Phase 6 — AOS: Cross-Customer Learning Autonomy (complete)

See `.planning/phases/06-cross-customer-learning/`

**Goal:** Lessons learned in one customer auto-promote to universal when the same pattern recurs across ≥2 customers (≥3 combined occurrences, ≥60% Jaccard token-overlap similarity). Anti-patterns route to bootstrap; conflicts surface for manual review.

**Exit gate:** Tier 12 24/24 + Tier 7/8/9/10/11 retained — confirmed `bash scripts/ark-verify.sh --tier 7` 14/14, `--tier 8` 25/25, `--tier 9` 20/20, `--tier 10` 22/22, `--tier 11` 16/16, `--tier 12` 24/24.

| Plan | Outcome |
|------|---------|
| 06-01 | `scripts/lib/lesson-similarity.sh`: Jaccard token-overlap primitive (sourceable Bash 3 lib); `lesson_similarity <a> <b>` returns 0..100; 14/14 self-test; real-lesson cross-pairs score 2–5% (meaningful cross-customer signal floor) |
| 06-02 | `scripts/lesson-promoter.sh`: discovery (`promoter_scan_lessons`) + clustering (`promoter_cluster`, ≥60% similarity) + classification (`promoter_classify` → PROMOTE/DEPRECATED/MEDIOCRE TSV); 18/18 self-test against isolated tmp portfolio; sentinel section laid for 06-03 apply-pending body |
| 06-03 | `promoter_apply_pending`: durable side-effects under mkdir-lock + atomic tmp+mv; managed-section format on universal-patterns.md and anti-patterns.md; per-cluster canonical marker for idempotency; `_policy_log lesson_promote PROMOTED|DEPRECATED|MEDIOCRE_KEPT_PER_CUSTOMER` audit class minted |
| 06-04 | `scripts/ark` `promote-lessons` subcommand (manual surface, default `--since 7-days-ago --apply`); `scripts/ark-deliver.sh::run_phase` post-phase hook (after Phase 3 policy-learner trigger; `--since 1-hour-ago --apply`; non-fatal); both routes use sourced-subshell invocation to bypass single-flag CLI dispatcher |
| 06-05 | Tier 12 verify suite: synthetic 3-customer fixture (8 lessons), 24 checks (10 wiring/static + 14 dynamic-pipeline) under mktemp portfolio + tmp git vault + tmp policy.db; real-vault md5 invariant for universal-patterns.md, anti-patterns.md, policy.db; idempotency assertions on re-run |
| 06-06 | REQ-AOS-31..39 minted (this plan); STATE.md Phase 6 close + drift reconciliation; ROADMAP.md checkboxes flipped; STRUCTURE.md AOS Cross-Customer Learning Contract; SKILL.md Phase 6 posture |

## Phase 6.5 — AOS: CEO Dashboard (complete)

See `.planning/phases/06.5-ceo-dashboard/`

**Goal:** Read-only CEO dashboard over Phase 2-6 audit data. Three-tier delivery:
Tier A (`ark dashboard` — bash, <2s) for the quick win; Tier B (`ark dashboard --tui` —
Rust ratatui binary with 2s live refresh) for proper interactive surface; Tier C
(`ark dashboard --web [--port N]` — bash + python3 stdlib http.server) for browser
access from the local machine (and trivial LAN access via `--bind 0.0.0.0`).

**Exit gate:** Tier 13 30/30 + Tier 7-12 retained — confirmed `bash scripts/ark-verify.sh --tier 7` 14/14, `--tier 8` 24/25 (1 pre-existing failure unrelated to dashboard, deferred to Phase 7 backlog), `--tier 9` 20/20, `--tier 10` 22/22, `--tier 11` 16/16, `--tier 12` 24/24, `--tier 13` 30/30.

| Plan    | Outcome |
|---------|---------|
| 06.5-01 | `scripts/ark-dashboard.sh` (Tier A — bash). All 7 sections render in <2s. Bash 3 compat. NO_COLOR + tput-degrade graceful fallback. Read-only via `sqlite3 -readonly`. |
| 06.5-02 | `scripts/ark` dispatcher: `dashboard` subcommand routes to Tier A by default; `--tui` routes to Tier B Rust binary; help text updated. |
| 06.5-03 | `scripts/ark-dashboard/` Rust crate scaffold: ratatui + rusqlite (bundled) + crossterm; no async runtime; SQLITE_OPEN_READ_ONLY enforced at C-API. |
| 06.5-04 | Sections 1-3 (portfolio, escalations, budget) implemented as `Section` trait; terminal raw-mode loop with restore-on-Drop. |
| 06.5-05 | Sections 4-7 (recent decisions, learning watch, drift detector, tier health) + 2s live refresh + vim keybindings (j/k/q/Tab/Enter/r). r-mark-resolved delegates to existing single-writer (`ark escalations --resolve`). |
| 06.5-06 | Tier 13 verify suite (30 checks, mktemp-isolated synthetic vault, real-vault md5 invariant on policy.db + ESCALATIONS.md + universal-patterns.md + anti-patterns.md). Tier 7-12 regression sweep clean (Tier 8 baseline 24/25 — pre-existing). |
| 06.5-07 | REQ-DASH-01..10 minted (this plan); STATE.md Phase 6.5 close + drift reconciliation; ROADMAP.md Phase 6.5 entry; STRUCTURE.md AOS CEO Dashboard Contract; SKILL.md Phase 6.5 posture. |
| 06.5-08 | `scripts/ark-dashboard-web.sh` (Tier C — bash + python3 stdlib http.server). Same 7 sections rendered as auto-refreshing HTML page. Default port 7919; `--port N` override; `ARK_DASHBOARD_PORT` env. Polling-trap cleanup pattern (≤1s shutdown latency on Ctrl-C, bash 3 compat). HTML-escape pipeline + atomic tmp+mv writes. |

**Substrate note:** Phase 6.5 sits between Phase 6 (Cross-Customer Learning) and Phase 7 (Continuous Operation). Mirrors the Phase 2.5 pattern: a substrate phase between two roadmap'd phases delivered ahead of where the original ROADMAP.md anticipated it ("Phase 8 reporting"). Phase 7 will consume this dashboard for async progress visibility.

**Tier 8 deferred item (Phase 7 backlog):** Tier 8 baseline regressed from 25/25 to 24/25 prior to Phase 6.5 (the pre-existing failure is `ark escalations subcommand dispatches`, unrelated to the dashboard). Per scope-boundary discipline, 06.5-06 logged this as a deviation rather than fixing it in this phase. Phase 7 should investigate and restore.

## Phase 7 — AOS: Continuous Operation (complete)

See `.planning/phases/07-continuous-operation/`

**Goal:** Cron-driven INBOX consumption. User authors intent in markdown at `~/vaults/ark/INBOX/`; macOS launchd daemon ticks every 15 min, parses intent, dispatches to `ark create` / `ark deliver --phase N` / `ark deliver` (portfolio) / `ark promote-lessons`, archives processed files to `INBOX/processed/<UTC-date>/`, escalates failures via `ESCALATIONS.md`, writes weekly digest. **Closes the AOS journey.**

**Exit gate:** Tier 14 28/28 + Tier 7/9/10/11/12/13 retained — confirmed `bash scripts/ark-verify.sh --tier 7` 14/14, `--tier 9` 20/20, `--tier 10` 22/22, `--tier 11` 16/16, `--tier 12` 24/24, `--tier 13` 30/30, `--tier 14` 28/28. Tier 8 baseline 24/25 carried forward (pre-existing failure on `ark escalations subcommand dispatches`, predates Phase 6.5; deferred to Phase 8 backlog per CONTEXT.md scope boundary).

| Plan  | Outcome |
|-------|---------|
| 07-01 | `scripts/lib/inbox-parser.sh` — frontmatter parser + intent dispatcher; sourceable Bash 3 lib; 16/16 self-test |
| 07-02 | `scripts/ark-continuous.sh` — main daemon: tick + `process_inbox` + mkdir-lock + daily token cap; 12/12 self-test; 8 audit-class decisions wired (`TICK_START`, `TICK_COMPLETE`, `INBOX_DISPATCH`, `INBOX_PROCESSED`, `INBOX_FAILED`, `INBOX_MALFORMED`, `LOCK_CONTENDED`, `DAILY_CAP_HIT`) |
| 07-03 | `continuous_health_monitor` — stuck-phase detection (24h STATE.md mtime + 24h no-commits) + 3-tick consecutive escalation (60-min window, 24h dedupe per project+phase) + auto-pause on 3 consecutive failure-ticks (`STUCK_PHASE_DETECTED`, `STUCK_ESCALATED`, `AUTO_PAUSE_3_FAIL`, `PAUSE_ACTIVE` audit classes) |
| 07-04 | `continuous_install` / `uninstall` / `status` / `pause` / `resume` subcommand bodies + atomic plist generator (`com.ark.continuous.plist`); `ARK_LAUNCHAGENTS_DIR` test override for hermetic Tier 14 plist generation |
| 07-05 | `scripts/ark::cmd_continuous` dispatcher arm: 6 subcommands (install / uninstall / status / pause / resume / tick) as pure pass-through to `ark-continuous.sh`; help text updated |
| 07-06 | `scripts/ark-weekly-digest.sh` — 6-section aggregator (projects shipped, phases completed, escalations, lesson promotions, budget burn, dashboard URL) + standalone `com.ark.weekly-digest.plist` (Sunday 09:00 local, independent cron); `WEEKLY_DIGEST_WRITTEN` audit class |
| 07-07 | Tier 14 verify suite (28 checks): 3-intent INBOX lifecycle (resume + new-phase + promote-lessons) + 3 safety rails (PAUSE / DAILY_CAP_HIT / LOCK_CONTENDED) + `plutil -lint` plist validation + weekly-digest 6-section assertion + `read -p` regression sweep across 3 continuous-path scripts + real-vault md5 invariants (`policy.db`, `ESCALATIONS.md`, `universal-patterns.md`, `anti-patterns.md`) + real `~/Library/LaunchAgents` md5 invariants (test runs use `ARK_LAUNCHAGENTS_DIR` override) |
| 07-08 | REQ-AOS-40..48 minted (this plan); STATE.md Phase 7 close + plan-count drift reconciliation + AOS journey terminal note + Phase 8 backlog (Tier 8 24/25 carry-forward, goldiejz/acme-sd repo, Phase 1 unchecked items); ROADMAP.md Phase 7 checkboxes + AOS-complete banner; STRUCTURE.md AOS Continuous Operation Contract; SKILL.md Phase 7 posture + AOS-complete state |

**AOS journey closed (Phases 2 → 2.5 → 3 → 4 → 5 → 6 → 6.5 → 7).** Original ROADMAP.md AOS goal achieved: user authors intent in markdown, walks away, returns to find projects shipped (or true blockers escalated via async ESCALATIONS.md queue). Phase 6.5 (CEO Dashboard) is read-only AOS visibility surface; Phase 7 (Continuous Operation) is the autonomy-loop closer. Phase 8 (Production Hardening) is post-AOS productionization, not autonomy.

**Tier 8 deferred (Phase 8 backlog):** Tier 8 baseline 24/25 pre-existing failure (`ark escalations subcommand dispatches`, unrelated to continuous operation) carried forward from Phase 6.5. Phase 7 did not touch this scope (per CONTEXT.md out-of-scope boundary). Phase 8 should investigate and restore to 25/25.

## Phase 8 — Future (post-AOS productionization)

Next per `.planning/ROADMAP.md`: **Phase 8 — Production Hardening & Reporting**. Multi-machine vault sync verification, disaster-recovery drill (restore from backup, verify state), investor/customer report templates, cross-project portfolio analytics dashboard, stress-test continuous-operation daemon under load. **Phase 8 is OUTSIDE the AOS journey** — it productionizes the AOS contract that closed at Phase 7, but does not extend the autonomy contract itself.

Phase 8 should also investigate/repair the Tier 8 pre-existing failure noted in the Phase 7 backlog above.
