---
id: strategix-ioc-L-006
title: HaloPSA `excludefromsla=true` must short-circuit SLA calculations
date_captured: 2026-04-21
origin_project: strategix-ioc
origin_repo: ioc
scope: ["integration", "assurance"]
severity: HIGH
applies_to_domains: ["ioc", "halopsa"]
customer_affected: [strategix]
universal: false
---

## Rule

Any derived SLA signal from a third-party ticketing system MUST honour the system's own "exclude from SLA" switch as the first guard, before any deadline arithmetic. When the upstream system has an explicit opt-out, computing our own answer from raw timer fields overrides the upstream intent. The test that catches this: past-deadline ticket + `excludefromsla=true` ⇒ `slaIsBreached=false`, `slaDataPresent=false`, regardless of `onhold`.

## Trigger Pattern

On `2026-04-21`, ticket #241354 (a PSO Change Request closed in the HaloPSA UI) showed as breached on the IOC Wall. Root cause: `computeSlaStatus` only checked `slaactiondate`/`fixbydate` and `onhold`. It ignored `excludefromsla`, a tenant-wide HaloPSA flag that opts a ticket out of SLA tracking entirely. 53 of 61 currently-breached-open tickets in prod carried this flag across 10+ ticket types — i.e. ~87% of the Breached pane was false positives.

## Mistake

Source lesson title: "HaloPSA `excludefromsla=true` must short-circuit SLA calculations"

## Cost Analysis

- Not specified in source lesson.

## Evidence

[`src/connectors/halopsa/sla.ts`](src/connectors/halopsa/sla.ts#L23), [`src/connectors/halopsa/sla.test.ts`](src/connectors/halopsa/sla.test.ts)

## Effectiveness

- Not specified in source lesson.

## Cross-Project History

- Not specified in source lesson.

## Related

- [[strategix-ioc-L-001]]
- [[strategix-L-018]]
