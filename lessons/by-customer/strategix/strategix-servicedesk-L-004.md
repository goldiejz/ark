---
id: strategix-servicedesk-L-004
title: Validate Codex model against active auth tier before enabling review gate
date_captured: 2026-04-22
origin_project: strategix-servicedesk
origin_repo: servicedesk
scope: ["process", "delivery"]
severity: HIGH
applies_to_domains: ["*"]
customer_affected: [strategix]
universal: true
---

## Rule

- **Always** dry-run `codex-companion.mjs review --wait --scope working-tree` (or equivalent) before enabling `--enable-review-gate` on a repo — treat a successful review as a prerequisite.
- **Always** pin `~/.codex/config.toml` `model` to a value the active ChatGPT auth tier is known to serve (`gpt-5.4` confirmed working 2026-04-22; `gpt-5.3-codex-spark` is an alternative).
- **Never** assume a Codex config change is harmless because it loaded without error — Codex validates models at first API call, not at config parse.
- **Always** prefer the `task` and `adversarial-review` subcommands (which accept `--model`) over `review` (which uses the global default) when per-invocation model control is needed.


## Trigger Pattern

Session enabled `codex:setup --enable-review-gate` on this repo while `~/.codex/config.toml` was set to `model = "gpt-5.2-codex"`. Stop-time review hook then failed every turn with a Codex API 400 — the ChatGPT-account auth tier does not serve `gpt-5.2-codex`. Every subsequent session close was blocked by a failing hook. Fix was to disable the gate, switch model to `gpt-5.4`, dry-run `review --wait` to confirm the path succeeds end-to-end, then re-enable.

## Mistake

Enabling a stop-time hook that depends on a Codex model without first confirming the active auth tier actually serves that model. The failure does not surface at config-load time; it surfaces at first tool call — which, for the stop gate, means every session close is blocked.

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
