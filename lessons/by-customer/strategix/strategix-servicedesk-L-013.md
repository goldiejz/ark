---
id: strategix-servicedesk-L-013
title: Sub-agent dispatch uses the 4-tier overseer + subordinate + rescue-gate pipeline
date_captured: 2026-04-23
origin_project: strategix-servicedesk
origin_repo: servicedesk
scope: ["process", "delivery"]
severity: HIGH
applies_to_domains: ["*"]
customer_affected: [strategix]
universal: true
---

## Rule

- **Always** for any non-trivial review / research fan-out that would otherwise use ≥2 parallel sub-agents: dispatch exactly **one overseer** on the higher-capability model (Sonnet or Opus); the overseer spawns subordinates.
- **Always** let the overseer pick subordinate models per task: Haiku for wide mechanical reads / pattern scans; Sonnet for judgement-heavy lenses. Mixed is explicitly encouraged.
- **Always** give subordinates distinct non-overlapping lenses (L-012 still applies) and have the overseer — not the main turn — synthesise their findings into one structured punch list.
- **Always** route remediation through `/codex:rescue` as a gate between the overseer's findings and the final QA pass. The main turn does not hand-patch code it just reviewed.
- **Always** have the main turn re-run the original acceptance criteria against the post-rescue tree as the closing QA step, before updating `STATE.md` or declaring done.
- **Never** parallelise two `general-purpose` or two Sonnet agents directly from the main turn when the work justifies the hierarchy (≥2 lenses, schema-level or doctrine-level review, multi-file surface).
- **Never** skip the rescue gate even if the overseer's punch list is small — the gate exists so "review" and "fix" live in different seats.


## Trigger Pattern

Global `~/.claude/CLAUDE.md` added two lines under §Parallelism discipline (2026-04-23): (a) "If required to use sub-agents, spin a overseer agent on a higher model to review, and the sub-agents as subordinates to the overseer using models such as sonnet or haiku or or mixed to execute to save tokens." (b) "Use /codex:rescue to review the code haiku or sonnet pushed before submitting back to the QA process." Yesterday's fallback adversarial review (see L-012) used a flat two-Sonnet peer pattern — correct on lens diversity, but ~4× the token cost of the prescribed hierarchy, and without a remediation gate.

## Mistake

Dispatching sub-agents in a flat peer configuration directly from the main turn, with identical model tier across all workers, and folding the remediation loop back into the main turn by hand. This burns higher-tier tokens on wide reads that Haiku does fine, and conflates "review" with "fix" in the same seat.

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
