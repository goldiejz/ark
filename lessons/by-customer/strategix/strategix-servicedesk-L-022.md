---
id: strategix-servicedesk-L-022
title: Tailwind `peer-*` selectors compile to `.peer ~ .target`; peer must precede target in source order
date_captured: 2026-04-24
origin_project: strategix-servicedesk
origin_repo: servicedesk
scope: ["process", "delivery"]
severity: HIGH
applies_to_domains: ["servicedesk"]
customer_affected: [strategix]
universal: false
---

## Rule

- **Always** when using Tailwind `peer-*` or `group-*` modifiers, place the `.peer` / `.group` element BEFORE any element that depends on its state. `~` (peer) and space-descendant (group) are both forward-only; out-of-order siblings produce no match.
- **Always** after any Tailwind state-selector change (`peer-*`, `group-*`, `has-*`, `aria-*`), render the result in a browser with the target state active — not just snapshot tests or typecheck — because these selectors fail silently when the compiled CSS doesn't match the DOM order.
- **Never** assume that "they're siblings now" is enough for `peer-*` to work. Check source order before declaring the fix done.
- **Always** when dispatching a Codex fix for a selector-level bug, include in the brief the exact Tailwind rule being relied on (e.g. "`peer-*` compiles to `.peer ~ .target`; peer must precede target") so Codex doesn't rely on memory of the rule. Naming the compile output turns a 50/50 heuristic into a deterministic fix.


## Trigger Pattern

Pass 1F drift fix pass. D-007 was "floating label doesn't rise when input has a value" on `/login`. First Codex pass moved the label `<span>` into the same flex container as the `<input>` (both now siblings) — but placed the span BEFORE the input. The `peer-[:not(:placeholder-shown)]` selector still didn't fire because Tailwind `peer-*` compiles to the general sibling combinator `~`, which requires the peer class to appear before the target in source order. The span (target) was before the input (peer), so the selector looked for `.peer ~ span` where no such relationship existed. Fix required reordering: `<input .peer />` first, then `<span>{label}</span>` as a later sibling.

## Mistake

Reading the Tailwind rule "`peer-*` classes react to a sibling with the `peer` class" and concluding that "make them siblings" is sufficient. The CSS generated is `.peer ~ .peer-<state>\:<utility>`, and `~` is strictly forward-looking — the `.peer` element must precede the element with the `peer-*` utility. Any fix that makes them siblings but puts the target first will silently do nothing, and the failure mode is invisible (no error, just no style applied), so a visual smoke test is the only way to catch it.

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
