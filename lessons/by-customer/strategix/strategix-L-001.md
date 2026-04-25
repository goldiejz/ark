---
id: strategix-L-001
title: Keep planning in Claude, offload coding to Codex
date_captured: 2026-04-22
origin_project: strategix-servicedesk
origin_repo: servicedesk
scope: ["planning/coding", "process"]
severity: HIGH
applies_to_domains: ["*"]
customer_affected: [strategix]
universal: false
---

## Rule

- **Always** author `.planning/*.md`, `CLAUDE.md`, `DOCS.md`, `README.md`, `tasks/*.md`, and vault pages directly in Claude.
- **Always** offload product code (routes, schema, UI components, tests, migrations, seed data, wrangler config, CI workflow body beyond stub) to the Codex plugin via `codex:rescue` or direct `codex` CLI handoff.
- **Always** have Claude review Codex output, run adversarial review passes, and update `STATE.md` — Codex never edits `STATE.md`, `ALPHA.md`, `ROADMAP.md`, `PROJECT.md`, or `REQUIREMENTS.md`.
- **Never** let Codex edit planning, doctrine, or truth files. If Codex starts touching those, the split has drifted and needs correction.

## Trigger Pattern

User directive at Day 0 bootstrap: _"keep the planning with claude and offload any coding to /codex plugin"_. This pattern ensures the audit trail clearly separates "who decided what" (Claude) from "who built what" (Codex), preventing planning drift and maintaining clear responsibility boundaries.

## Mistake

Blurring the planning/coding split by having either agent author content outside its domain. Claude writing product code bypasses review discipline; Codex writing planning files loses the trail of architectural decisions.

## Cost Analysis

- **Estimated cost to ignore:** Blurred decision audit trail, unclear ownership of architectural choices, planning/code drift that compounds across sessions.
- **How many projects paid for this lesson:** 1 (strategix-servicedesk, rule established Day 0).
- **Prevented by this lesson:** Maintains audit clarity across all future delegations.

## Evidence

- Origin: Day 0 bootstrap user directive (2026-04-22)
- Established as L-001 in servicedesk lessons

## Effectiveness

- **Violations since capture:** 0 (enforced from inception)
- **Prevented by this lesson:** Serves as the root discipline for all planning/coding handoffs
- **Last cited:** 2026-04-22

## Cross-Project History

- **Strategix (origin):** Established 2026-04-22, enforced throughout Phase 1.

## Related

- Complementary to: [[strategix-L-015]] (docs commits on main)
- Part of: [[doctrine/shared-conventions#Planning-Coding-Discipline]]
- Enforced by: [[planning-phase-researcher]], [[gsd-executor]]

---

*Captured 2026-04-22 during strategix-servicedesk bootstrap*
