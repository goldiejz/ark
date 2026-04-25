---
id: strategix-servicedesk-L-010
title: Phase claims in design.md must reconcile with the 4 doctrine sources in the same commit
date_captured: 2026-04-23
origin_project: strategix-servicedesk
origin_repo: servicedesk
scope: ["process", "delivery"]
severity: HIGH
applies_to_domains: ["*"]
customer_affected: [strategix]
universal: true
---

## Rule

- **Always** before writing any "Phase X" / "Phase 1.5" / "Phase 2" claim into a non-authoritative doc, grep the 4 truth sources (`CLAUDE.md`, `.planning/PROJECT.md`, `.planning/ALPHA.md`, `.planning/ROADMAP.md`) for the same module name and confirm agreement.
- **If sources disagree**, surface the contradiction in the same turn, propose reconciliation paths, and get a scope decision before committing — not after.
- **Never** let a design-canon document be the authoritative source for phase placement. Design canon references phase; it does not define it.
- **Never** commit a phase reclassification without updating every doctrine source that contradicts it, in the same commit.


## Trigger Pattern

Commit `3e41960` added a Problem Management brief to `tasks/design-reference/design.md` claiming "Phase 1.5 placement". Adversarial review found that `CLAUDE.md` (repo), `.planning/PROJECT.md`, `.planning/ALPHA.md`, and `.planning/ROADMAP.md` all placed Problem Management in Phase 2. Four authoritative sources disagreed with one non-authoritative doc. Fixing the drift required a follow-up reconciliation commit (`c80ae12`, "Path C").

## Mistake

Writing a scope/phase claim into a design-canon or brief file (`design.md`, `halopsa-observations.md`, vault pages) without cross-checking the 4 doctrine sources that own phase truth. Drift accumulates silently because design docs are visually persuasive and doctrine files are rarely re-read.

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
