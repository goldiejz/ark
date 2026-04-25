---
id: strategix-L-020
title: Shell rebuilds must audit affordance continuity across breakpoints
date_captured: 2026-04-24
origin_project: strategix-servicedesk
origin_repo: servicedesk
scope: ["frontend", "responsive-design", "UX"]
severity: HIGH
applies_to_domains: ["*"]
customer_affected: [strategix]
universal: true
---

## Rule

- **Always** when a brief introduces a shell rebuild or new responsive-visibility pattern (`hidden md:flex`, `md:block`, etc.), enumerate every pre-existing affordance in the old shell (sign-out, new-ticket, notifications, help, user menu, avatar, search, back button) and confirm each has a visible path at every breakpoint in the new shell.
- **Always** when dispatching adversarial review of a shell rebuild, add an explicit "affordance continuity across breakpoints" lens as one of the subordinate lenses.
- **Always** when a Codex brief says "move X into Y" without specifying the breakpoint visibility of Y, treat that as a brief-silent-on-responsive-behaviour failure and require either a brief amendment or an explicit fallback rule before dispatching.
- **Never** ship a shell rebuild whose only mobile-layout assertion is "pnpm build succeeded" — the build does not execute any breakpoint-specific rendering.

## Trigger Pattern

Pass 1F commit `acde05d` (PortalShell rebuild) moved the `signOut()` button from the always-visible header into a new left rail with `hidden md:flex`. Below the `md` (768px) breakpoint the rail disappears, and the mobile-visible header block (line 77) was not given a replacement logout affordance. Pre-1F `main` had Sign out in the header at all breakpoints, so the commit silently stripped mobile customers of their only logout path on the Refreshed portal. Adversarial review lenses (visual fidelity, scope compliance, sibling-drift) all missed this because none was scoped to "compare the pre-commit affordance surface against the post-commit affordance surface, per breakpoint."

## Mistake

Treating a shell rebuild as a "move the existing pieces to the new layout" problem when the new layout has responsive visibility rules the old layout didn't. A pre-existing affordance (sign-out, new-ticket, user menu, help) that was unconditionally visible becomes conditionally visible as soon as it's relocated into a responsively-hidden container, and the conditional visibility regression is invisible to typecheck / tests / desktop-pixel-matching.

## Cost Analysis

- **Estimated cost to ignore:** Locked-out users on mobile portal (cannot log out), support tickets, reputation damage, 4-8 hours to diagnose responsive breakpoint issue.
- **How many projects paid for this lesson:** 1 (strategix-servicedesk, fixed post-commit in f015182).
- **Prevented by this lesson (estimate):** 1-2 per project doing shell work.

## Evidence

- Commit that surfaced it: `acde05d` (PortalShell rebuild, caught by Codex stop-hook)
- Adversarial review finding: "affordance continuity across breakpoints" lens was missing
- Related to: [[strategix-L-022]] (Tailwind `peer-*` sibling source order), [[universal-patterns#Responsive-Design-Regressions]]

## Effectiveness

- **Violations since capture:** 0 (lesson is recent, 2026-04-24).
- **Prevented by this lesson (potential):** 2-3 across services/ioc if they do mobile-focused shell work.
- **Last cited:** 2026-04-24

## Cross-Project History

- **Strategix (origin):** Discovered 2026-04-24 on PortalShell rebuild (1F), fixed same commit via stop-hook.
- **Strategix CRM:** Minimal mobile work; likely low recurrence risk.
- **Strategix IOC:** No mobile portal (internal-only); different risk profile.

## Related

- Prevents anti-pattern: "Silent affordance regression on mobile breakpoints"
- Part of: [[doctrine/shared-conventions#Responsive-Design-Testing]]
- Sibling lesson: [[strategix-L-022]] — Tailwind `peer-*` source order
- Advisory lens for reviews: "affordance continuity across breakpoints"

---

*Captured 2026-04-24 during Codex stop-hook review of 1F shell rebuild*
