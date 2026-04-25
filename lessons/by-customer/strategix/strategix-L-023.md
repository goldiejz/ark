---
id: strategix-L-023
title: STATE.md `## Counts` table updates atomically with the code change, not just the narrative
date_captured: 2026-04-24
origin_project: strategix-servicedesk
origin_repo: servicedesk
scope: ["documentation", "STATE.md", "truth hierarchy"]
severity: HIGH
applies_to_domains: ["*"]
customer_affected: [strategix]
universal: true
---

## Rule

- **Always** when a commit adds or removes tests, API routes, UI pages, migrations, tables, seed rows, roles, event types, or build-size bytes: update the corresponding row in the `## Counts` table of `.planning/STATE.md` in the same commit. The Counts table is not optional; it is the machine-readable truth surface and ranks equal with the narrative.
- **Always** treat the Counts table as a post-narrative checklist: after the narrative is written, re-read each relevant row and verify the number still holds against the new commit.
- **Never** carry forward a stale qualifier like "unchanged by <prior pass>" without checking whether the current commit invalidates it. If a prior pass's note says "unchanged by Phase 2 schema branch" but the current commit DOES change the row, delete the qualifier and update the number.
- **Always** have adversarial reviewers cross-check Counts-table rows against the diff. Counts-vs-narrative disagreement is a named drift pattern; reviewers should look for it specifically.

## Trigger Pattern

Day B portal approval flow landed as commit `4cba9c3`. The commit correctly updated the narrative (new `MVP Day B` section) but left three rows in the `## Counts` table stale: `Tests (main)` still read 58 (13 files) after bringing the suite to 73 (17 files); `API routes` did not list the new `/api/portal/timesheets/*` surface; `UI pages` said 8 when new pages brought it to 10. Two truth surfaces in the same document disagreed — the exact drift-as-defect case that architectural standards define.

## Mistake

Writing the narrative update for a new pass and stopping before double-checking the Counts table. The narrative is what a reader reads first; the Counts table is how downstream reviewers and contradiction passes cross-reference live truth. Updating one and not the other creates split truth that is harder to spot than a simple omission — both sections look plausible in isolation.

## Cost Analysis

- **Estimated cost to ignore:** Split truth in the same document, downstream contradiction passes miss drift because they trusted the narrative, future sessions inherit the stale numbers as baseline.
- **How many projects paid for this lesson:** 1 (strategix-servicedesk, caught by adversarial review).
- **Prevented by this lesson:** Ensures single-document consistency across all future phases.

## Evidence

- Commit that surfaced it: `4cba9c3` (portal approval flow, caught in adversarial review)
- Pattern: STATE.md drift found across narrative and Counts sections simultaneously
- Related to: [[strategix-L-010]] (doctrine contradiction audits)

## Effectiveness

- **Violations since capture:** 0 (lesson is recent, 2026-04-24)
- **Prevented by this lesson (potential):** 1-2 per phase across all Strategix repos
- **Last cited:** 2026-04-24

## Cross-Project History

- **Strategix (origin):** Discovered 2026-04-24 on Day B portal closure. Applied to Phase 1 final closure.

## Related

- Prevents anti-pattern: "Split truth in same doc"
- Part of: [[doctrine/shared-conventions#Truth-Hierarchy]], [[~/.claude/CLAUDE.md#Drift-Rule]]
- Complementary to: [[strategix-L-010]] (doctrine contradiction audits)
- Enforced by: servicedesk-reviewer lens "counts-vs-narrative cross-check"

---

*Captured 2026-04-24 during Day B closure adversarial review*
