---
finding_id: strategix-schema-003
source: strategix-servicedesk
audit_id: migration-metadata-collision
audit_date: 2026-04-24
scope: schema-drift
verdict: PARTIAL
blocks_merge: false
severity: HIGH
origin_issue: fragmented migration metadata across branches
---

## Summary

Migration metadata (version counters, applied timestamps) fragmented across main branch and feature branches, risking collision during rebase/merge on multi-developer teams.

## Problem

When two branches both add migrations (0005_*, 0006_*), rebase order matters for applied-migration state. Without careful coordination, one branch's applied list disagrees with another's.

## Recommendation

**Short-term:** Manual migration rebase coordination before merge.

**Medium-term:** Implement migration validation hook that reads applied-migration manifest from D1 and verifies local migration file count matches; flag drift before deploy.

**Long-term:** Establish branch-naming convention for migrations (`migration/feature-name-*`) and enforce sequential numbering via pre-commit hook.

## Related Lessons

- L-021: Drizzle schema-first migrations own source of truth
- New lesson candidate: "Migration metadata must be managed sequentially across branches; use pre-commit hooks to validate local migration count against applied manifest"

## Cross-Repo Relevance

**Universal pattern:** Migration fragmentation is a multi-repo scaling pain. All three Strategix projects use D1 + Drizzle; coordinating migrations across parallel feature branches requires explicit discipline.

**Cost if ignored:** Failed deployments due to out-of-order migrations; data loss if rollback misses a migration; team friction during rebases.

**Prevention:** Pre-commit hook validates migration file sequencing; migration-naming convention signals intent (feature branch vs main).
