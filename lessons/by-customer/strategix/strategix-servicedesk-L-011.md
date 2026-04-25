---
id: strategix-servicedesk-L-011
title: Use `git apply --cached` for surgical staging when a working-tree file has mixed concerns
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

- **Always** when a working-tree file has mixed concerns, write the intended change as a unified-diff patch anchored against HEAD, then `git apply --cached <patch>` to mutate only the index. Working tree stays untouched.
- **Always** verify with `git diff --cached <file>` that the staged diff is exactly the intended scope before committing.
- **Always** keep the patch file on disk (e.g. `/tmp/<scope>-<date>.patch`) as an audit artifact for the commit — it documents exactly what was staged vs what was left behind.
- **Never** `git add` a file you haven't diff-read in full when you know the working tree wasn't clean when you started editing.


## Trigger Pattern

`codex:codex-rescue` applied Path C edits to `.planning/STATE.md` on disk, but the working tree already carried 66 lines of uncommitted Day A content in the same file. `git add STATE.md` would have bundled Day A into the Path C commit, violating the "minimal change" rule. `git add -p` is interactive and hard to automate cleanly.

## Mistake

When a single file mixes "the change I'm trying to commit" with "unrelated residue someone left in my working tree", the instinct is either (a) stash-commit-unstash (adds churn, risks conflicts on re-apply) or (b) `git add <file>` wholesale (bundles residue silently). Both are worse than surgical staging.

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
