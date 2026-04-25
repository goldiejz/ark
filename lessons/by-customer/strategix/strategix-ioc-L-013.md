---
id: strategix-ioc-L-013
title: Client components must not import server-bound modules — even if only using a small util
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

A "use client" component must only import from modules whose entire import graph is safe in the browser. If you want to share a tiny pure helper (date math, type constants, branding tokens) between client and server, extract it into its own module whose imports are themselves client-safe. Don't rely on tree-shaking to hide server deps. The test that catches this: `next build` produces a clean client bundle without pulling in D1 / connectors / server-SDK code.

## Trigger Pattern

TQR round-15 on 2026-04-21. `performance-tab.tsx` (marked `"use client"`) imported `getWeekStart` from `src/lib/tqr/batch.ts`. That module also imports `getDb`, HaloPSA connectors, and Anthropic fetch at top level. Next.js may tree-shake unused code from the client bundle but makes no guarantee; at best you bloat the bundle, at worst the server deps break the browser build.

## Mistake

Source lesson title: "Client components must not import server-bound modules — even if only using a small util"

## Cost Analysis

- Not specified in source lesson.

## Evidence

[`src/lib/tqr/week-utils.ts`](src/lib/tqr/week-utils.ts) (extracted client-safe util), [`src/lib/tqr/batch.ts`](src/lib/tqr/batch.ts) (re-exports for back-compat).

## Effectiveness

- Not specified in source lesson.

## Cross-Project History

- Not specified in source lesson.

## Related

- [[strategix-ioc-L-001]]
- [[strategix-L-018]]
