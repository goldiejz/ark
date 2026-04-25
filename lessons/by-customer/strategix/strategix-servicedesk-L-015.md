---
id: strategix-servicedesk-L-015
title: Docs commits go on `main`; feature branches are reserved for the work they're named after
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

- **Always** before any `git commit` on a session involving multiple branches: explicitly run `git branch --show-current` and confirm it's the intended branch. If it's not, `git switch` first, then commit.
- **Always** docs / planning / handoff / lessons / `.planning/STATE.md` commits land on `main` (or whatever the long-lived integration branch is). Feature branches carry only the feature.
- **Always** when a feature-branch marker depends on "no other commits ahead of main", verify post-commit with `git log --oneline main..<branch>` — empty pre-work means the marker is honest. If it's non-empty and you didn't mean it, FF main forward and re-verify.
- **Always** when handing off to a future session, prefer range-based markers (`git log main..feature`) over absolute-SHA markers ("anything newer than X"). Range markers are self-stable; SHA markers decay every commit.
- **Never** commit a doc that describes a marker rule onto the very branch the marker rule excludes — that's the self-reference loop that breaks the handoff.


## Trigger Pattern

Created `feat/pm-problem-schema` for Codex's Phase 2 schema work, then committed the session's docs/handoff/lessons updates onto that branch instead of `main`. Did it twice in the same session — once with `06edb1c`, then again with the supposed fix `ab761b4` (despite the fix's commit message explaining the exact problem). Codex stop-gate caught the first occurrence. The deeper issue: a feature branch named for X should contain only X. Mixing docs commits onto it makes any range-based marker ("commits on the branch but not main = Codex's work") lie.

## Mistake

Treating "I'm currently on branch Y, so my commit goes there" as good enough. Branch context drifts silently — `git switch` happens earlier in a turn, working tree edits accumulate, and by commit time HEAD may not be where you assumed. Combined with absolute-SHA markers in handoff docs, this produces a self-contradicting handoff: the very commit that documents the marker rule violates it.

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
