---
id: strategix-servicedesk-L-020
title: Shell rebuilds must audit every pre-existing affordance at every breakpoint before committing
date_captured: 2026-04-24
origin_project: strategix-servicedesk
origin_repo: servicedesk
scope: ["process", "delivery"]
severity: HIGH
applies_to_domains: ["servicedesk"]
customer_affected: [strategix]
universal: false
---

## Rule

- **Always** when a brief introduces a shell rebuild or a new responsive-visibility pattern (`hidden md:flex`, `md:block`, `lg:visible`, etc.), enumerate every pre-existing affordance in the old shell (sign-out, new-ticket, notifications, help, user menu, avatar, search, back button) and confirm each has a visible path at every breakpoint in the new shell. Write the affordance matrix into the brief: `affordance | old: always | new: md+ rail | mobile fallback: <x>`.
- **Always** when dispatching adversarial review of a shell rebuild, add an explicit "affordance continuity across breakpoints" lens as one of the subordinate lenses. Tokens / scope / sibling-drift are insufficient coverage for shells.
- **Always** when a Codex brief says "move X into Y" without specifying the breakpoint visibility of Y, treat that as a brief-silent-on-responsive-behaviour failure (same class as L-018 brief-silent-on-inheritance) and require either a brief amendment or an explicit fallback rule before dispatching.
- **Never** ship a shell rebuild whose only mobile-layout assertion is "pnpm build succeeded" — the build does not execute any breakpoint-specific rendering. Manual smoke at 375px is required, or Playwright responsive coverage, before declaring the shell green.
- **Never** rely on the Codex stop-hook to be the only defence against affordance regressions — stop-hook catches what it catches, but the cost of a missed one is a locked-out user on a branch that already claims "all gates green." Adversarial lens coverage must include the affordance matrix.


## Trigger Pattern

Pass 1F commit `acde05d` (PortalShell rebuild) moved the `signOut()` button from the always-visible header into a new left rail with `hidden md:flex`. Below the `md` (768px) breakpoint the rail disappears, and the mobile-visible header block (line 77) was not given a replacement logout affordance. Pre-1F `main` had Sign out in the header at all breakpoints, so the commit silently stripped mobile customers of their only logout path on the Refreshed portal. Adversarial review lenses (visual fidelity, scope compliance, sibling-drift on D-001/D-002/D-003) all missed this because none was scoped to "compare the pre-commit affordance surface against the post-commit affordance surface, per breakpoint." The Codex stop-hook — running after the remediation commit and re-scanning the PortalShell change — caught it on a third pass.

## Mistake

Treating a shell rebuild as a "move the existing pieces to the new layout" problem when the new layout has responsive visibility rules the old layout didn't. A pre-existing affordance (sign-out, new-ticket, user menu, help) that was unconditionally visible becomes conditionally visible as soon as it's relocated into a responsively-hidden container, and the conditional visibility regression is invisible to typecheck / tests / desktop-pixel-matching. Adversarial review lenses focused on tokens, scope, and drift classes won't catch it either — the drift is in the *affordance matrix*, not the code structure.

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
