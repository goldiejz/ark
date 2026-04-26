---
phase: 02-autonomy-policy
plan: 09
subsystem: docs
tags: [aos, docs, structure, requirements, state, phase-2-close]
requires: [02-01, 02-02, 02-03, 02-04, 02-05, 02-06, 02-06b, 02-07, 02-08]
provides:
  - "AOS Escalation Contract documentation in STRUCTURE.md"
  - "REQ-AOS-01..07 in .planning/REQUIREMENTS.md"
  - "Phase 2 complete marker in .planning/STATE.md"
  - "AOS Posture section in ~/.claude/skills/ark/SKILL.md"
affects:
  - STRUCTURE.md
  - .planning/REQUIREMENTS.md
  - .planning/STATE.md
  - ~/.claude/skills/ark/SKILL.md
key-files:
  modified:
    - STRUCTURE.md
    - .planning/REQUIREMENTS.md
    - .planning/STATE.md
    - ~/.claude/skills/ark/SKILL.md
decisions:
  - "Document audit-log schema_version=1 verbatim including decision_id/outcome/correlation_id (Phase-3-ready) so Phase 3 can patch outcomes in place without breaking schema"
  - "STATE.md Phase 2 block lists all 10 plans (including 02-06b) per INDEX wave structure"
  - "SKILL.md gains AOS Posture section pointing back to STRUCTURE.md as source of truth"
metrics:
  duration_minutes: ~5
  tasks_completed: 3
  files_modified: 4
  commits: 2
completed: "2026-04-26T13:15:00Z"
---

# Phase 2 Plan 02-09: STRUCTURE.md + skill docs Summary

One-liner: AOS Escalation Contract (4 true-blocker classes, locked policy-decisions.jsonl schema_version=1 with decision_id/outcome/correlation_id, cascading config order, layered self-heal contract) documented in STRUCTURE.md; REQ-AOS-01..07 minted; STATE.md marks Phase 2 complete.

## What shipped

### 1. STRUCTURE.md — AOS Escalation Contract section

Appended a locked `## AOS Escalation Contract` section after the existing `What ark align Does` section. Contents:

- **4 true-blocker classes table:** monthly-budget, architectural-ambiguity, destructive-op, repeated-failure with their decision functions in `scripts/ark-policy.sh`.
- **Queue location + format:** `~/vaults/ark/ESCALATIONS.md` with regex-stable section delimiter (`## ESC-YYYYMMDD-HHMMSS-<6char-rand> — <class> — <open|resolved>`).
- **Audit log schema (locked, schema_version=1):** Verbatim JSON example plus per-field semantics table (writer/reader split). Documents `decision_id` format as `%Y%m%dT%H%M%SZ-XXXXXXXXXXXXXXXX` (16-hex from `/dev/urandom`, 64-bit entropy) — matches the W-4 fix from Plan 02-01.
- **Decision values per class** enumeration (budget, dispatch, zero_tasks, dispatch_failure, escalation, self_heal).
- **Why Phase-3-ready fields ship in Phase 2:** Explained — Phase 3 patches outcome in place using decision_id as key.
- **Cascading config:** env > project > vault > defaults; lists keys consumed today.
- **Layered self-heal contract (3 layers):** count-file gating, ark-team retry-loop disambiguation, single `_policy_log` writer note.
- **Observer pattern:** `manual-gate-hit` reference + intentional-gate tag convention.
- **Cross-references:** Decision functions, escalation helper, layered retry script, Tier 8 verify, plan history.

Commit: `eef8240`

### 2. REQUIREMENTS.md — REQ-AOS-01..07

Appended 7 new rows after R-008. Each maps to a Phase 2 acceptance criterion in `CONTEXT.md` and points evidence at the relevant SUMMARY file(s):

| ID | Evidence pointer |
|----|------------------|
| REQ-AOS-01 | 02-08-SUMMARY.md |
| REQ-AOS-02 | 02-01, 02-03, 02-04, 02-05, 02-06, 02-06b |
| REQ-AOS-03 | 02-02-SUMMARY.md |
| REQ-AOS-04 | 02-01-SUMMARY.md, STRUCTURE.md |
| REQ-AOS-05 | 02-08-SUMMARY.md |
| REQ-AOS-06 | 02-07-SUMMARY.md |
| REQ-AOS-07 | 02-09-SUMMARY.md (this file) |

All status `done`. Existing R-001..R-008 untouched.

Commit: `e8cec9a`

### 3. STATE.md — Phase 2 complete

- Frontmatter `current_phase` advanced from `Phase 1 (GSD Integration)` to `Phase 2 (AOS: Delivery Autonomy)`, `status` from `in-progress` to `complete`, progress 9/10 → 19/20 (counts both phases' plans).
- Body header updated to match.
- Replaced `## Phase 2+ — Future [TBD]` placeholder with detailed `## Phase 2 — AOS: Delivery Autonomy (complete)` block listing all 10 plans (02-01 through 02-09 + 02-06b) with one-line outcomes.
- Exit gate documented: Tier 8 25/25 + Tier 1–7 14/14 retained.
- Phase 1 section left as-is (not in scope per plan).
- New `## Phase 3+ — Future` pointer to self-improving self-heal.

Commit: `e8cec9a`

### 4. SKILL.md — AOS Posture

Inserted `## AOS Posture (since Phase 2)` block after the top-of-file overview paragraph in `~/.claude/skills/ark/SKILL.md`. States Ark is in delivery-autonomy mode, lists the 4 true-blocker classes, points at the audit log path (`~/vaults/automation-brain/observability/policy-decisions.jsonl`) and STRUCTURE.md as schema source of truth.

Note: SKILL.md lives outside the vault git repo (under `~/.claude/skills/ark/`); no atomic commit available. Change is in place on disk.

## Verification

```bash
$ grep -c 'REQ-AOS-0[1-7]' .planning/REQUIREMENTS.md
7
$ grep -q 'Phase 2' .planning/STATE.md && echo OK
OK
$ grep -q 'AOS Escalation Contract' STRUCTURE.md && \
  grep -q 'schema_version' STRUCTURE.md && \
  grep -q 'decision_id' STRUCTURE.md && \
  grep -q 'correlation_id' STRUCTURE.md && \
  grep -qE 'monthly-budget|architectural-ambiguity|destructive-op|repeated-failure' STRUCTURE.md && \
  echo OK
OK
$ grep -q 'AOS Posture' ~/.claude/skills/ark/SKILL.md && echo OK
OK
```

All `<done>` block criteria satisfied for each task.

## Deviations from Plan

None — plan executed exactly as written. The `# Requirements` heading in REQUIREMENTS.md is a single header (no frontmatter), so legacy R-001..R-008 rows and new REQ-AOS rows live in one table. This matches the plan's "append rows" instruction.

## Known Stubs

None. All references in the new STRUCTURE.md section point at code/files that exist (verified by grep against `scripts/ark-policy.sh` decision-function names per the plan's `key_links`).

## Self-Check: PASSED

- STRUCTURE.md edits present (verified by grep above).
- REQUIREMENTS.md has 7 REQ-AOS-NN rows (verified count == 7).
- STATE.md updated to Phase 2 complete (verified header and frontmatter).
- SKILL.md AOS Posture section present (verified by grep).
- Commits `eef8240` and `e8cec9a` exist on `main` (verified via `git log`).
