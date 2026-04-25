---
id: strategix-servicedesk-L-008
title: Stitch-first design workflow beats screenshot-driven guessing
date_captured: 2026-04-22 (evening)
origin_project: strategix-servicedesk
origin_repo: servicedesk
scope: ["process", "delivery"]
severity: HIGH
applies_to_domains: ["servicedesk"]
customer_affected: [strategix]
universal: false
---

## Rule

- **Always** when a design-heavy pass is about to start, first create a Stitch project (`mcp__stitch__create_project`) + design system (`mcp__stitch__create_design_system`), then generate each canonical screen (`mcp__stitch__generate_screen_from_text`) with **prompts ≥ 600 words** that specify: chrome, layout grid, per-component positioning, exact copy, colour hex codes, typography scale, state (hover/focus/disabled), accessibility notes. Gemini 3.1 Pro honours detail.
- **Always** use `GEMINI_3_1_PRO` explicitly (the default model may be Flash — cheaper but less polished).
- **Always** expect Stitch to auto-evolve the design system mid-session when prompts get richer (happened 2026-04-22 — the simple system upgraded to "Precision Monolith" tonal-layering system with a deeper token scale). Let it; the new system is usually better.
- **Always** commit a `tasks/design-reference/design.md` index listing every Stitch screen ID with its path + title + design-system asset, so Codex (and future sessions) can fetch screens by ID without re-running generation.
- **Always** pass the Stitch project ID + screen IDs to Codex in the brief as the **authoritative design source** — Codex's first action is `mcp__stitch__get_screen` for each ID.
- **Never** skip Stitch when the pass is primarily visual. Even for a single screen, 3 minutes of generation saves hours of back-and-forth.
- **Never** rely on the Google-usercontent preview URLs as durable storage — they expire. Capture stable copies to `~/vaults/<project>/presentations/stitch-<date>/` or refetch from Stitch on demand.


## Trigger Pattern

User shared 19 HaloPSA reference screenshots across an afternoon, then said "run this through google stitch and if its not professional enough, dont come back to me until you feel it". Without Stitch, Claude would have been describing designs in markdown prose; Codex would have been inventing visual detail from Claude's prose. With Stitch (Gemini 3.1 Pro-backed), Claude produces fully-rendered canonical screens that double as executable design specs — Codex fetches the HTML export and has a complete Tailwind reference page to mirror.

## Mistake

Jumping from "here are screenshots" straight to "Codex, build a React UI that looks like this" — the spec gets lost in translation twice (screenshot → Claude prose → Codex interpretation). Visual fidelity is always the weakest link in a design implementation pass.

## Cost Analysis

- Not specified in source lesson.

## Evidence

- Origin: `strategix-servicedesk/tasks/lessons.md`

## Effectiveness

- Not specified in source lesson.

## Cross-Project History

- Not specified in source lesson.

## Related

- [[strategix-L-001]]
- [[strategix-L-023]]
