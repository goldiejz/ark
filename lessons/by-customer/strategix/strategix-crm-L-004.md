---
id: strategix-crm-L-004
title: PROJECT.md must not carry temporal status claims
date_captured: 2026-04-20
origin_project: strategix-crm
origin_repo: crm
scope: ["revops", "governance"]
severity: HIGH
applies_to_domains: ["crm"]
customer_affected: [strategix]
universal: false
---

## Rule

`PROJECT.md` captures durable intent and architectural shape only. Any constraint whose wording contains a temporal qualifier ("today", "not yet", "currently", "none") must either (a) be promoted to `STATE.md` and linked from `PROJECT.md`, or (b) be rephrased to describe the durable architectural decision and defer live status to `STATE.md`. When `STATE.md` flips a closure that was previously referenced as an absent-constraint in `PROJECT.md` (e.g. C3-01 staging), update `PROJECT.md` in the same change — and sweep the programme-level vault (`programme-status.md`, compliance docs, audit findings) for the same stale wording. Failing that sweep is what turns a single stale line into programme-wide drift.

**Sub-rule (observed on 2026-04-20 when fixing exactly this drift):** option (b) is easy to botch. When rephrasing a constraint, do NOT mirror the live specifics from `STATE.md` (project name, database UUID, branch name, CI job name, deploy URL, secret name, auth product). Those are mutable and belong in `STATE.md` only. Keep `PROJECT.md` at the durable-architectural-commitment layer, and let `STATE.md` own every concrete name. If the rephrased constraint still contains a name that could change if the environment were rebuilt, it is still drift-in-waiting — cut further.

**Sub-rule (second botch, observed same turn):** even the durable-architectural sentence itself can lie about the current delivery path. Writing "staging sits between dev and prod; changes flow through it before prod" during a phase when the pipeline still deploys directly from `main` to prod (C3-03 open) is a false-current-state claim dressed as durable intent. The ambient temptation is to describe the *intended* pipeline as if it were the current one. Rule: when the durable phrasing makes a behavioural claim ("X flows through Y before Z"), check `STATE.md` + the open `ROADMAP.md` phase items — if any gate behind that behaviour is still open, the phrasing is aspirational and belongs in `ROADMAP.md` / `ALPHA.md`, not `PROJECT.md`.

**Sub-rule (third botch realised same turn — structural):** the `Staging` line never belonged in `PROJECT.md > Constraints` in the first place. A Constraints section captures binding architectural choices (auth product, runtime platform, currency, tenancy, platform-level limits). Whether a staging environment currently exists, and what role it plays in the promotion flow, is a delivery-pipeline concern with its own phased lifecycle (`C3` in `ROADMAP.md`). Phased topics should not be represented in `PROJECT.md` at all — they appear and disappear on phase cadences and therefore drift. Rule: before adding a bullet to `PROJECT.md > Constraints`, ask whether the bullet could change via a `ROADMAP.md` phase closure. If yes, it does not belong in `PROJECT.md` — keep it in `STATE.md` / `ROADMAP.md` and leave `PROJECT.md` out of the loop entirely.

**Sub-rule (fourth botch — stale-bullet triage):** when correcting a stale risk bullet in `programme-status.md` (or any risks register), do NOT delete it just because the wording no longer matches reality. A risk bullet typically bundles a condition ("staging does not exist") with a consequence ("changes go straight to prod-like D1 untested"). A phase closure may eliminate the condition while leaving the consequence active — here, `C3-01` gave us a staging environment, but `C3-03` has not yet made prod deploys depend on a staging pass, so the "changes reach prod untested" consequence is still live. Rule: on any stale-risk correction, decompose the bullet into (condition, consequence) and check each against `STATE.md` + open `ROADMAP.md` items. Delete only when both are resolved; otherwise rewrite the bullet to reflect the residual risk and cite the open phase item that would close it. Dropping a bullet outright on a partial resolution is programme-level under-reporting.

**Sub-rule (fifth botch — doctrine imperative language):** phase-definition lines in doctrine files (e.g. `~/vaults/StrategixMSPDocs/programme.md > Strategic Phase Model`) are often written with imperative verbs ("close X", "Build Y", "make Z a real gate"). That wording reads as a pending-task list and contradicts `STATE.md` the moment any of those items close — but doctrine files are not status files and don't self-mark as fixed. Here, `programme.md` Phase 0 still said "Build staging and make CI a real gate" after `C3-01` had closed the staging build, so programme doctrine gave one deployment posture while `STATE.md` gave another. Rule: phase definitions in doctrine must be written in declarative phase-scope form ("this phase's scope: X, Y, Z") with an explicit pointer to `STATE.md` / `ROADMAP.md` for live progress. Imperative verbs in doctrine are a smell — they turn the doctrine into a shadow status register that drifts silently.

## Trigger Pattern

A contradiction audit on 2026-04-20 found `.planning/PROJECT.md:39` still said `Staging: None today. Changes go directly from local dev to production D1 via wrangler.` while `.planning/STATE.md:25` said staging was live and C3-01 closed on 2026-04-19. The stale claim also propagated out to `~/vaults/StrategixMSPDocs/programme-status.md` (Programme-Level Risks block), because downstream readers trusted PROJECT.md for the constraint wording and mirrored it there. Both files had to be corrected.

## Mistake

Treated `PROJECT.md` as a place to note current operational reality ("None today") rather than durable scope. The word "today" inside a doctrine/scope file is the smell: any "today", "not yet", "none currently", "no staging" style phrasing inside PROJECT.md is a time-bomb because PROJECT.md is rarely re-read when C-phase items close.

## Cost Analysis

- Not specified in source lesson.

## Evidence

- Origin: `strategix-crm/tasks/lessons.md`

## Effectiveness

- Not specified in source lesson.

## Cross-Project History

- Not specified in source lesson.

## Related

- [[strategix-crm-L-001]]
- [[strategix-L-025]]
