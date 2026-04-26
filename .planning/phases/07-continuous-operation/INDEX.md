# Phase 07 — AOS: Continuous Operation — Plan Index

This phase is split into 8 plans across 6 waves. Wave-1 builds the INBOX
parser foundation. Wave-2 builds the daemon core (tick + dispatch + lock + cap)
that sources the parser. Wave-3 fans out into health monitor (extends daemon)
and weekly digest (independent). Wave-4 wires subcommands + plist generator.
Wave-5 wires the `ark continuous` dispatcher arm. Wave-6 verifies via Tier 14.
Wave-7 closes Phase 7 (and AOS) — mints REQ-AOS-40..48 and updates
STATE/ROADMAP/STRUCTURE/SKILL.

| Plan  | Title                                                                                  | Wave | Depends on | Files modified |
|-------|----------------------------------------------------------------------------------------|------|------------|----------------|
| 07-01 | scripts/lib/inbox-parser.sh — frontmatter + intent dispatcher; sourceable; self-test   | 1    | —          | scripts/lib/inbox-parser.sh |
| 07-02 | scripts/ark-continuous.sh — main daemon: tick + process_inbox + lock + daily cap        | 2    | 07-01      | scripts/ark-continuous.sh |
| 07-03 | continuous_health_monitor — stuck-phase detection + 3-tick consecutive escalation       | 3    | 07-02      | scripts/ark-continuous.sh (extension section) |
| 07-04 | continuous_install/uninstall/status/pause/resume + launchd plist generator              | 4    | 07-02, 07-03 | scripts/ark-continuous.sh (subcmd section) |
| 07-05 | scripts/ark dispatcher: `ark continuous <subcmd>` wiring                                | 5    | 07-04      | scripts/ark |
| 07-06 | scripts/ark-weekly-digest.sh — weekly digest generator + standalone launchd plist       | 3    | 07-02      | scripts/ark-weekly-digest.sh |
| 07-07 | Tier 14 verify suite — synthetic 3-intent INBOX fixture; mktemp; assert lifecycle       | 6    | 07-04, 07-05, 07-06 | scripts/ark-verify.sh |
| 07-08 | STRUCTURE.md AOS Phase 7 contract; REQ-AOS-40..48; STATE.md + ROADMAP.md + SKILL.md     | 7    | 07-07      | STRUCTURE.md, .planning/REQUIREMENTS.md, .planning/STATE.md, .planning/ROADMAP.md, SKILL.md |

## Wave structure

- **Wave 1:** 07-01 (INBOX parser primitive — every other plan consumes it).
- **Wave 2:** 07-02 (daemon core: tick loop, mkdir-lock, daily token cap, INBOX
  file lifecycle: process → `processed/<date>/`, `.failed`, `.malformed`. Lays
  sentinel sections for 07-03's health-monitor body and 07-04's subcommand body).
- **Wave 3:** 07-03 + 07-06 in parallel (disjoint files).
  - 07-03 extends `scripts/ark-continuous.sh` inside the
    `# === SECTION: health-monitor (Plan 07-03) ===` region.
  - 07-06 creates a brand-new `scripts/ark-weekly-digest.sh` and ships its own
    plist generator (separate launchd job from the main daemon).
- **Wave 4:** 07-04 (subcommands + plist generator, extends ark-continuous.sh
  inside `# === SECTION: subcommands (Plan 07-04) ===`). Depends on 07-03 so
  `status` can include health-monitor state.
- **Wave 5:** 07-05 (dispatcher arm in `scripts/ark`; pure pass-through to
  ark-continuous.sh). Disjoint file from 07-04.
- **Wave 6:** 07-07 (Tier 14 verify; needs full pipeline live including
  weekly digest invocation).
- **Wave 7:** 07-08 (docs close + REQ minting; AOS journey terminal plan).

## Wave-3 file-conflict note

07-03 and 07-06 are runnable in parallel:
- 07-03 modifies `scripts/ark-continuous.sh` only inside the
  `# === SECTION: health-monitor (Plan 07-03) ===` … `# === END SECTION ===`
  region laid down by 07-02.
- 07-06 creates `scripts/ark-weekly-digest.sh` (new file) and
  `~/Library/LaunchAgents/com.ark.weekly-digest.plist` template (in-script
  generator, no on-disk file installed during plan).
- No overlapping files. Wave-3 fan-out is safe.

## Requirements coverage

REQ-AOS-40..REQ-AOS-48 map 1:1 to the 9 Phase 7 acceptance criteria in
CONTEXT.md. IDs are minted in plan frontmatter; rows added to
`.planning/REQUIREMENTS.md` by 07-08.

| Req         | Statement | Covered by |
|-------------|-----------|------------|
| REQ-AOS-40  | scripts/ark-continuous.sh exists; sourceable; self-test passes | 07-02 |
| REQ-AOS-41  | INBOX intent file is processed on next tick → moved to processed/<date>/ | 07-01, 07-02 |
| REQ-AOS-42  | launchd plist at ~/Library/LaunchAgents/com.ark.continuous.plist installable via `ark continuous install` | 07-04, 07-05 |
| REQ-AOS-43  | `ark continuous status` shows last tick, next tick, recent decisions, daily token used | 07-04, 07-05 |
| REQ-AOS-44  | `ark continuous pause` creates PAUSE file; `ark continuous resume` removes it | 07-04, 07-05 |
| REQ-AOS-45  | Health monitor detects synthetic stuck phase + escalates after 3 ticks | 07-03 |
| REQ-AOS-46  | Weekly digest generates ~/vaults/ark/observability/weekly-digest-YYYY-WW.md | 07-06 |
| REQ-AOS-47  | Tier 14 verify: synthetic INBOX with 3 intent files → assert all processed correctly | 07-07 |
| REQ-AOS-48  | Existing Tier 1–13 still pass (no regression) | 07-07 |

## Phase 2/3/4/5/6/6.5 lessons honored (avoid regression)

- **Single audit writer:** All `continuous` class entries go through `_policy_log`
  from `ark-policy.sh`. No inline `INSERT INTO decisions`. Mirrors Phase 2 NEW-B-2
  + Phase 3 single-writer rule.
- **Bash 3 compat (macOS):** No `declare -A`, no `mapfile`, no `${var,,}`. Use
  `tr` for case folds, `awk` for parsing and integer math, `sort -u` for dedup.
- **No `read -p` in delivery-path or daemon scripts:** `ark-continuous.sh`,
  `inbox-parser.sh`, and `ark-weekly-digest.sh` contain zero `read -p`. Tier 14
  includes a regression check (skipping comment lines + the verify suite's own
  test region — Phase 4 self-referential test pattern lesson).
- **mkdir-lock not flock:** `~/vaults/ark/.continuous.lock` uses `mkdir`
  (atomic on macOS, no flock). Mirrors Phase 3 03-03 `_lrn_acquire_lock`.
- **Atomic file writes:** INBOX file moves via `mv` (atomic on same FS); weekly
  digest writes via `tmp + mv`; plist writes via `tmp + mv`. No partial-state
  artifacts.
- **Phase-4 GitHub-incident lesson:** Tier 14 fixture MUST NOT touch real
  `~/vaults/ark/`, real `~/Library/LaunchAgents/`, invoke `launchctl load` on a
  real plist, or invoke any `gh` / `ark create` that hits real GitHub. Use
  `mktemp -d` for vault root + plist target dir; set `ARK_HOME=$TMP_VAULT`,
  `ARK_LAUNCHAGENTS_DIR=$TMP_LA`, and `ARK_CREATE_GITHUB=false` (default). Real
  policy.db md5 captured before/after; assertion that md5 unchanged.
- **Self-referential test pattern trap (Phase 4 lesson):** the `read -p`
  regression check in 07-07 must skip the test/comment lines themselves
  (`grep -v '^[[:space:]]*#'` + exclude verify-suite's own region by line range
  or marker).
- **ARK_CREATE_GITHUB env gate:** any Tier 14 path that exercises the
  `new-project` intent must set `ARK_CREATE_GITHUB=false` explicitly (default
  off; gate carried forward from Phase 4).
- **Idempotency:** re-running tick over same INBOX produces no duplicate
  audit rows; `processed/<date>/` files are never re-processed (file is gone
  from INBOX); plist generator is idempotent (regenerate writes byte-identical
  output absent script changes).
- **Real-vault md5 invariant:** Tier 14 captures `md5 policy.db ESCALATIONS.md`
  before + after the synthetic tick. Assertion that real policy.db md5
  unchanged. Mirrors Phase 5/6/6.5.
- **No self-modifying daemon:** continuous-operation script does NOT promote
  its own patterns to itself. Phase 3's policy-learner operates on delivery
  patterns only; continuous-operation patterns are out of scope per CONTEXT.md.

## Locked decisions from CONTEXT.md (verbatim — do not revisit)

- **D-CONT-DAEMON:** macOS launchd user-agent at
  `~/Library/LaunchAgents/com.ark.continuous.plist`. Default `StartInterval` is
  `tick_interval_min * 60` seconds (default 15 min). User-level (loads on login,
  not system daemon).
- **D-CONT-INBOX-FORMAT:** Markdown files in `~/vaults/ark/INBOX/*.md` with
  YAML-ish frontmatter (`intent`, `customer`, `priority`). Filename
  `YYYY-MM-DD-short-slug.md`. Body = description.
- **D-CONT-INTENTS:** Four intents only —
  `new-project | new-phase | resume | promote-lessons`. Dispatch table:
  - `new-project` → `ark create "$description" --customer "$customer"`
  - `new-phase` → `ark deliver --phase $N` (project resolved from frontmatter)
  - `resume` → `ark deliver` (portfolio engine picks)
  - `promote-lessons` → `ark promote-lessons`
- **D-CONT-LIFECYCLE:** Process success → `mv` to
  `~/vaults/ark/INBOX/processed/<date>/`. Failure → rename in place with
  `.failed` extension + ESCALATIONS.md entry. Parse failure → `.malformed`
  extension + log reason. Files never silently dropped.
- **D-CONT-LOCK:** `~/vaults/ark/.continuous.lock` mkdir-style. Held for
  duration of tick. Manual `ark deliver` takes precedence (daemon defers to
  next tick if lock contended at tick start).
- **D-CONT-PAUSE:** `~/vaults/ark/PAUSE` file is the kill-switch. Daemon
  checks PAUSE first on every tick; presence → exit 0 (no-op). Auto-pause:
  3 consecutive failure-ticks → daemon auto-creates PAUSE + writes
  ESCALATIONS.md entry (idempotent).
- **D-CONT-DAILY-CAP:** `policy.yml::continuous.daily_token_cap` (default
  50000). Cap exceeded → SUSPENDED for rest of day (until UTC date rollover).
  Logged via `_policy_log "continuous" "DAILY_CAP_HIT" ...`.
- **D-CONT-HEALTH:** Stuck-phase detection — active phase with no STATE.md
  modification in >24h AND no recent commits. 3 consecutive ticks (~45 min
  default) of stuck signal → escalate ONCE (idempotent dedupe via correlation_id
  on `_policy_log "continuous" "STUCK_PHASE_DETECTED" ...`).
- **D-CONT-WEEKLY-DIGEST:** Separate launchd job at
  `~/Library/LaunchAgents/com.ark.weekly-digest.plist`, scheduled Sunday 09:00
  local. Reads `policy-decisions.jsonl` (or sqlite policy.db) for the week.
  Sections: projects shipped · phases completed · escalations resolved ·
  learner promotions · budget burn · dashboard URL. Writes to
  `~/vaults/ark/observability/weekly-digest-YYYY-WW.md` via tmp+mv.
- **D-CONT-AUDIT-CLASS:** All decisions logged via
  `_policy_log "continuous" "<DECISION>" ...`. Decisions:
  `TICK_START | TICK_COMPLETE | INBOX_PROCESSED | INBOX_FAILED | INBOX_MALFORMED |
   STUCK_PHASE_DETECTED | DAILY_CAP_HIT | AUTO_PAUSED | LOCK_CONTENDED | PAUSE_ACTIVE |
   WEEKLY_DIGEST_WRITTEN`.
- **D-CONT-PLATFORM:** macOS launchd only. Linux cron variants out of scope
  (Phase 8 if user goes Linux).
- **D-CONT-SCOPE-OUT:** No Slack/email push, no multi-machine coordination,
  no real-time/event-driven processing, no self-modifying daemon code.
