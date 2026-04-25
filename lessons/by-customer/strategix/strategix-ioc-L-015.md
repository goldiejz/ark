---
id: strategix-ioc-L-015
title: withAudit HOF must cover both returned responses AND thrown exceptions
date_captured: 2026-04-20
origin_project: strategix-ioc
origin_repo: ioc
scope: ["integration", "assurance"]
severity: CRITICAL
applies_to_domains: ["*"]
customer_affected: [strategix]
universal: true
---

## Rule

HOFs that instrument route behaviour for observability must run their instrumentation on every exit path, not just the happy path. Use a `try { return await handler() } catch { synthesize status } finally { log }` pattern (or equivalent) so success, 4xx, AND thrown 5xx all emit the audit row. Re-throw the caught error after scheduling the audit so upstream error handling (Next.js default 500, error boundaries) still runs. Any audit wrapper that claims "every request is audited" MUST pass a "throw inside the handler" regression test.

## Trigger Pattern

Codex adversarial-review on `2026-04-20` noted that `withAudit` only inserted the audit row after `await handler(...)` returned a Response. Any handler that threw (schema error, network hiccup, uncaught db error) bypassed audit entirely — the exact 500s forensic reconstruction needs most would leave no trail.

## Mistake

Source lesson title: "withAudit HOF must cover both returned responses AND thrown exceptions"

## Cost Analysis

- Not specified in source lesson.

## Evidence

- Not specified in source lesson.

## Effectiveness

- Not specified in source lesson.

## Cross-Project History

- Not specified in source lesson.

## Related

- [[strategix-ioc-L-001]]
- [[strategix-L-018]]
