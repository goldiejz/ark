---
id: strategix-crm-L-009
title: JSON body parsing must narrow to a non-null object before property access
date_captured: 2026-04-20
origin_project: strategix-crm
origin_repo: crm
scope: ["revops", "governance"]
severity: HIGH
applies_to_domains: ["*"]
customer_affected: [strategix]
universal: true
---

## Rule

At every handler that parses a JSON body, parse as `unknown` first, then narrow explicitly: `if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) return 400`. Only after the narrow check may the handler access properties on `body`. Add a test for each endpoint that sends `body: 'null'` and asserts 400 — it's the cheapest regression guard against "200 dev tools, 500 prod JSON gremlin" divergence.

## Trigger Pattern

Same Codex review found that `await c.req.json<T>().catch(() => ({}))` returns the parsed JSON literally when it's valid JSON. Literal `null`, arrays, numbers, strings are all valid JSON but are not objects — the `.catch` never fires, and subsequent `body.notes` / `Object.prototype.hasOwnProperty.call(body, ...)` throws a `TypeError` surfaced as a 500. This is easy for an internal caller, retrying proxy, or accidental `JSON.stringify(null)` to trigger.

## Mistake

Assuming that because the happy-path input is always an object, `await req.json()` always yields one. That's not the JSON contract — it's just what the typical client happens to send.

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
