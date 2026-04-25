---
id: strategix-crm-L-002
title: Run D1 migrations automatically after push
date_captured: 2026-04-08
origin_project: strategix-crm
origin_repo: crm
scope: ["revops", "governance"]
severity: HIGH
applies_to_domains: ["*"]
customer_affected: [strategix]
universal: true
---

## Rule

Always run `npx wrangler d1 execute strategix-crm --file=<migration> --remote` automatically after pushing code with new migrations

## Trigger Pattern

Pushing code that includes new migrations

## Mistake

Suggested the user run the migration manually instead of executing it

## Cost Analysis

- Not specified in source lesson.

## Evidence

- Origin: `strategix-crm/tasks/lessons.md`

## Effectiveness

- Not specified in source lesson.

## Cross-Project History

- Not specified in source lesson.

## Related

- [[strategix-crm-L-001]]
- [[strategix-L-025]]
