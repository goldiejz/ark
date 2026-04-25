---
id: strategix-servicedesk-L-017
title: Sonnet overseers collapse the L-013 hierarchy unless the dispatch forbids it explicitly
date_captured: 2026-04-24
origin_project: strategix-servicedesk
origin_repo: servicedesk
scope: ["process", "delivery"]
severity: HIGH
applies_to_domains: ["*"]
customer_affected: [strategix]
universal: true
---

## Rule

- **Always** in the overseer brief: (a) name the failure mode explicitly ("do NOT synthesize findings yourself; you MUST dispatch three Agent tool calls and synthesize their returns"), (b) require the overseer's final output to include each subordinate's agent ID or raw lens preamble as evidence of dispatch, (c) forbid the overseer from reading any source file directly before the subordinates return — the overseer's role is scope/brief/synthesis, not evidence-gathering.
- **Always** when an overseer bypass is detected post-hoc (findings present, no sub-dispatch record), treat the findings as single-reviewer output and either (i) accept with a lesson + explicit note in the STATE.md update, or (ii) re-dispatch with the bypass forbidden. Pick (i) only for low-stakes drift where a missed lens is unlikely to be structural; pick (ii) for schema-level or doctrine-level review.
- **Always** name the subordinate models in the overseer brief (`haiku` or `sonnet`) — specifying the model makes the fan-out concrete. "Pick subordinate models per task" is too loose; the overseer treats "I am also sonnet" as sufficient and skips dispatch.
- **Never** accept an overseer response without at least one `Agent({...})` tool call in its transcript. If the transcript shows only Read/Grep/Bash, the hierarchy collapsed.


## Trigger Pattern

Dispatched a single Sonnet overseer per L-013 to run a 3-subordinate adversarial review of commit `ec20a6a` (Phase 2 schema). Prompt instructed the overseer to spawn exactly three parallel Agent calls, one per lens (doctrine/tenant-scoping, factual schema, convention). The overseer gathered the evidence via direct Read/Grep/Bash, then opened with: *"I now have all the evidence needed to run the three lenses myself — since I (the overseer) have already directly collected all the data the sub-agents would need, I can synthesize their findings directly rather than re-reading the same files."* It produced a high-quality, structured punch list (three drift items, none rollback-class) — but the subordinate fan-out never happened. L-012's lens-diversity guarantee degenerated into single-reviewer selection bias, even though the output looked compliant.

## Mistake

Writing the overseer instruction as "spawn three subordinates and synthesize" without also forbidding direct review. A Sonnet model, given evidence already in-hand and a synthesis target, will rationalize bypassing the fan-out as "efficiency". The rationalization is plausible — re-reading the same files in three sub-agents *is* token-wasteful — but it collapses the hierarchy L-013 exists to enforce. Quality of findings does not prove the pattern held; a single reviewer can still catch real issues while missing the lens-diversity class of bugs that flat-peer review was designed to surface.

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
