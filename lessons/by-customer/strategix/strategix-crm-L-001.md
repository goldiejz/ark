---
id: strategix-crm-L-001
title: Config-in-D1 must fail closed at every consumer, not just the write path
date_captured: 2026-04-21
origin_project: strategix-crm
origin_repo: crm
scope: ["schema", "configuration", "governance"]
severity: HIGH
applies_to_domains: ["*"]
customer_affected: [strategix]
universal: true
---

## Rule

- **Always** when moving a value from code into a D1 table, grep for every remaining import of the old constant and classify each consumer:
  - (a) preview-only — fallback is OK, document it
  - (b) commercial artefact / signed output — must gate on load state and fail closed if unavailable
  - (c) historical record — must snapshot at write time so reprints reproduce agreed numbers
- **Never** rationalize fallbacks individually ("previews need to render", "the server has authority"). Fallbacks compound into a defect where finance edits a rate but downstream code silently uses the hardcoded old value.
- **Always** update every consumer in the same migration that moves the config to the database.

## Trigger Pattern

`commitment_discount_curves` was already the DB-backed source of truth for pricing discounts, but three consumers silently fell back to a hardcoded constant: the server loader on empty table, `useCommitmentRates` during the fetch window, and `QuotePrintPage` which imported the constant directly. The governance layer (RBAC + audit on PATCH) was ignored by downstream code that bypassed the store entirely. When finance edited a rate, what was printed for the customer did not change.

## Mistake

Treated the config migration as "done" once reads and writes were wired, without auditing every place that still imported the original constant. Fallbacks were rationalized individually and compounded into a defect where financial policy changes don't propagate to all consumers.

## Cost Analysis

- **Estimated cost to ignore:** Silent pricing inconsistency, customer disputes, audit trail mismatch, 2-4 days root-cause work.
- **How many projects paid for this lesson:** 1 (strategix-crm, discovered during A3 phase).
- **Prevented by this lesson:** Grep discipline at config migration time stops silent fallbacks.

## Evidence

- Commit: A3 phase (2026-04-21)
- Pattern: Config migrated to D1, but hardcoded constants still imported in three places

## Effectiveness

- **Violations since capture:** 0 (lesson is recent, 2026-04-21)
- **Prevented by this lesson (potential):** 1-2 per config-in-DB migration across projects
- **Last cited:** 2026-04-21

## Related

- Part of: [[doctrine/shared-conventions#Configuration-Management]]
- Complementary to: [[universal-patterns#Config-in-DB Must Fail Closed]]
- Enforced by: code-reviewer lens "grep for old constant names"

---

*Captured 2026-04-21 during strategix-crm A3 config audit*
