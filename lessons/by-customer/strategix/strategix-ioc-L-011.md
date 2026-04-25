---
id: strategix-ioc-L-011
title: Module-global `lastRequestTime` throttle is a race under concurrency
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

Any throttle whose state is a module-global `lastTime`-style counter MUST use a serial mutex (promise-chain queue) when concurrency is possible, not a read-then-check-then-update. The mutex's critical section is "wait for previous holder → measure elapsed → maybe delay → update lastTime → release." Without the mutex, concurrency transparently defeats the throttle. The test that catches this: fire N concurrent throttled calls, assert they actually serialize (check elapsed between consecutive completions >= THROTTLE_MS).

## Trigger Pattern

Same TQR automation review (round-5). The pre-existing HaloPSA client throttle read `lastRequestTime`, computed elapsed, and conditionally slept — a read-then-update pattern. At concurrency > 1 (added by `runTqrBatch` 5-wide), all N callers observed the same stale `lastRequestTime` before any wrote it back, all computed `elapsed >= THROTTLE_MS`, and all bypassed the delay. The 1.5s gap between calls collapsed to ~0.

## Mistake

Source lesson title: "Module-global `lastRequestTime` throttle is a race under concurrency"

## Cost Analysis

- Not specified in source lesson.

## Evidence

[`src/connectors/halopsa/client.ts`](src/connectors/halopsa/client.ts) (`acquireHaloThrottle` chain-promise queue).

## Effectiveness

- Not specified in source lesson.

## Cross-Project History

- Not specified in source lesson.

## Related

- [[strategix-ioc-L-001]]
- [[strategix-L-018]]
