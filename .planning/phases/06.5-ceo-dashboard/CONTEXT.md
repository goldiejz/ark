# Phase 6.5 — CEO Dashboard — Context

## Why this phase exists

Phases 2-6 made AOS autonomous. Phase 7 (next) makes it continuously operating via cron — meaning Ark will make decisions, ship code, promote lessons, and reset budgets *while you're not watching*.

Without a dashboard, the only signal is `ESCALATIONS.md` (true blockers) and weekly digests. That's enough for blockers, blind for routine activity. Before Phase 7 makes "Ark working without you" the default, Phase 6.5 delivers visibility.

This is the "what's Ark doing right now?" answer.

## Position in AOS roadmap

Phase 6.5 sits between Phase 6 (just shipped) and Phase 7 (Continuous Operation):
- Phase 6: cross-customer lesson promotion (data layer complete)
- **Phase 6.5: CEO Dashboard** (visibility layer — read-only over Phases 2-6 audit data)
- Phase 7: cron-driven autonomous operation (uses Phase 6.5 to surface progress to user)

This phase mirrors Phase 2.5 (SQLite migration): a substrate phase between two roadmap'd phases that the original ROADMAP.md anticipated only loosely as "Phase 8 reporting." Pulling it forward because Phase 7 needs it.

## Two-tier delivery (autonomous defaults — no grilling)

### Tier A: Bash `ark dashboard` (quick win, 1 day)
- Single bash subcommand reading `policy.db` (sqlite3 CLI) + `ESCALATIONS.md` + verification reports
- Pull-style — runs once, prints colored terminal report, exits
- Sections: portfolio grid · escalations queue · budget summary · recent decisions · learning patterns · drift detector
- Reuses existing `run_check`-style ANSI coloring from `ark-verify.sh`
- Ships in days, immediate value

### Tier B: Rust TUI dashboard (proper, 3-5 days)
- Built with `ratatui` (terminal UI) + `rusqlite` (read SQLite directly)
- Live refresh via 2s polling of policy.db (cheap with WAL mode)
- Vim-style keybindings (j/k navigate, q quit, r mark resolved, Enter drill-down)
- Same sections as Tier A, but interactive — drill into a row, see decision history, jump to source files
- Build via `cargo build --release` in `scripts/ark-dashboard/`
- Single binary output: `~/vaults/ark/scripts/ark-dashboard-bin`
- `ark dashboard` (no flag) runs Tier A; `ark dashboard --tui` runs Tier B

## Data sources (read-only over Phases 2-6 outputs)

- **Audit log** — `~/vaults/ark/observability/policy.db` (SQLite). Every decision class:
  - `bootstrap`, `budget`, `dispatch`, `dispatch_failure`, `escalation`, `lesson_promote`, `portfolio`, `self_heal`, `self_improve`, `zero_tasks`
- **Escalations queue** — `~/vaults/ark/ESCALATIONS.md`
- **Weekly digests** — `~/vaults/ark/observability/policy-evolution.md`
- **Universal patterns** — `~/vaults/ark/lessons/universal-patterns.md`
- **Anti-patterns** — `~/vaults/ark/bootstrap/anti-patterns.md`
- **Verification reports** — `~/vaults/ark/observability/verification-reports/*.md`
- **Per-project STATE.md** — `~/code/*/.planning/STATE.md`
- **Per-project budget** — `~/code/*/.planning/budget.json`

Dashboard is **strictly read-only**. It NEVER writes to policy.db, ESCALATIONS.md, or any vault file. Mark-resolved actions are the one exception — they invoke `ark escalations --resolve <id>` which uses the existing single-writer path.

## CEO dashboard sections (priority order, both tiers)

1. **Portfolio grid** — projects × current phase × last activity × health (green/yellow/red)
2. **Escalations panel** — count of pending blockers by class (4 true-blocker types); list view
3. **Budget summary** — per-customer monthly burn, headroom percent, ESCALATE_MONTHLY_CAP risk
4. **Recent decisions stream** — last 50 rows from `policy.db` filtered/grouped by class
5. **Learning watch** — patterns approaching promotion threshold (≥3 customers but <60% similarity yet); patterns just promoted
6. **Drift detector** — STATE.md vs disk reality (catches the drift class 06-03 surfaced)
7. **Tier health** — last verify report's pass/fail count per tier (7-12); link to report

## Acceptance criteria (Phase 6.5 exit)

1. `scripts/ark-dashboard.sh` exists; `ark dashboard` invokes it
2. All 7 sections render with real data from this vault
3. Read-only: real policy.db md5 unchanged before/after run
4. Bash version runs in <2s on a populated vault (61+ rows)
5. Rust TUI builds via `cd scripts/ark-dashboard && cargo build --release`
6. Rust TUI launches via `ark dashboard --tui` and refreshes live (2s poll)
7. Tier 13 verify: synthetic vault with seeded data → assert each section's pass criterion
8. Existing Tier 1-12 still pass (no regression)

## Constraints

- Bash 3 compat for the bash version (macOS)
- Rust toolchain assumed available (already required for the prior dashboard scaffold)
- Single-writer audit unchanged: dashboard READS, doesn't write
- No new top-level `read -p` (delivery-path discipline holds for dashboard too — escalation actions go through the existing `ark escalations --resolve` path)
- Atomic-ish: dashboard never partially-renders; bash version uses tput/ANSI to clear screen between sections
- Color-friendly to terminals without 256-color (degrade gracefully)

## Out of scope

- Web dashboard (Phase 8 candidate; networking/auth/sync overhead)
- Push notifications (Slack/macOS); the queue surface is enough for v1
- Multi-machine sync (single-laptop vault)
- Historical trend charting (Phase 7 weekly-digest covers this textually)
- Plug-in "employees" UI surface in v1 (registry exists; Tier B can show role rows; richer plugin model = Phase 8)

## Risks

1. **Bash sqlite3 calls slow on large policy.db** — mitigated by indexed queries (Phase 2.5 added 4 indexes on the table); should stay <1s on 10k rows
2. **Rust TUI dependency creep** — pin to ratatui + rusqlite + crossterm only; no async runtime, no serde derives beyond what's needed
3. **Read-during-write WAL race** — SQLite WAL mode handles this natively (readers see consistent snapshot); no extra locking needed
4. **Drift detector false positives** — STATE.md hand-edits during active phases will trip it; mitigated by 60s tolerance window and by surfacing as INFO not RED
