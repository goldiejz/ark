---
id: strategix-ioc-L-014
title: Aborted batches must return non-2xx — silent success masks partial failure
date_captured: 2026-04-21
origin_project: strategix-ioc
origin_repo: ioc
scope: ["integration", "assurance"]
severity: HIGH
applies_to_domains: ["*"]
customer_affected: [strategix]
universal: true
---

## Rule

A batch that stopped early for external-cost or external-dependency reasons MUST be surfaced as non-2xx by the HTTP wrapper, even if the batch itself returns partial results. The semantics are: 200 = "we processed the whole budget without an abort-class event"; 503 = "external dependency or budget exhausted, retry later." The response body can still carry the partial result so operators can inspect progress, but the status code is what monitoring reads. Applies to both the manual route AND the cron endpoint — Cloudflare's scheduled() handler considers a successfully-resolved fetch as "cron succeeded" by default, so monitoring can't tell partial runs from full success from logs alone.

## Trigger Pattern

TQR rounds 16 and 18 on 2026-04-21. First drafts let `runTqrBatch` return `{ aborted: true, abortReason: "CREDITS_EXHAUSTED" }` inside an HTTP 200 response. The UI only checked `response.ok` and `ticketsScored`, so an aborted batch that scored 0 rendered as "Scored 0 tickets" instead of "Claude credits exhausted." Monitoring on the cron side saw a 200 and didn't alert.

## Mistake

Source lesson title: "Aborted batches must return non-2xx — silent success masks partial failure"

## Cost Analysis

- Not specified in source lesson.

## Evidence

[`src/app/api/v1/cron/tqr-score-batch/route.ts`](src/app/api/v1/cron/tqr-score-batch/route.ts), [`src/app/api/v1/tqr/run/route.ts`](src/app/api/v1/tqr/run/route.ts), [`cron-worker/src/index.ts`](cron-worker/src/index.ts) (`console.error` on res.status >= 400).

## Effectiveness

- Not specified in source lesson.

## Cross-Project History

- Not specified in source lesson.

## Related

- [[strategix-ioc-L-001]]
- [[strategix-L-018]]
