---
id: strategix-servicedesk-L-012
title: Adversarial review dispatches two sub-agents with distinct lenses, not two identical ones
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

- **Always** when falling back from `codex:adversarial-review` to sub-agent review, pick at least two distinct lenses (e.g. doctrine vs facts, security vs performance, correctness vs idiomatic) and brief each lens separately with non-overlapping scope.
- **Always** tell each review sub-agent what the *other* lens is covering, so they don't duplicate and so the user can see the review matrix is covered.
- **Always** require a structured output (Contradictions / Drift / Violations / Clean) from each reviewer so synthesis into a punch list is mechanical, not interpretive.
- **Never** use two `general-purpose` agents in parallel for adversarial review — diversity of lens is the whole point.


## Trigger Pattern

Fallback adversarial review for commit `3e41960` was needed because `codex:adversarial-review` wasn't available in the local skill registry. Dispatched two sub-agents in parallel with distinct briefs: `general-purpose` for doctrine-contradiction scanning (read STATE/ALPHA/ROADMAP/PROJECT and look for phase/scope drift), `code-reviewer` for diff-factual accuracy (verify Stitch ID uniqueness, screen-count math, markdown syntax, route collisions). Both returned structured findings with near-zero overlap — doctrine reviewer caught the Phase 1.5/2 contradiction; factual reviewer caught the stale "pending" heading.

## Mistake

Dispatching two parallel review agents with the same prompt, or the same agent type twice. They converge on the same findings, waste tokens, and give false confidence (two agents agreed → must be right). Real adversarial coverage comes from orthogonal review lenses.

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
