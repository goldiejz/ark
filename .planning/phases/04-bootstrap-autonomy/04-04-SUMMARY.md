# Plan 04-04 — ark-create.sh wired to bootstrap-policy: Summary

**Status:** COMPLETE (with one production-side-effect incident handled)
**Date:** 2026-04-26

## Files modified

- `scripts/ark-create.sh` — wired `bootstrap_classify` for description-mode invocation; preserved flag-based path for backward compat; atomic CLAUDE.md/policy.yml writes; `_policy_log "bootstrap"` audit entries; `ark_escalate architectural-ambiguity` on LOW_CONFIDENCE; **`ARK_CREATE_GITHUB` env gate** around `gh repo create`.

## Smoke tests

- Description-mode: `ark create "service desk for testco" --customer testco --path /tmp/...` → produces project, no leftover `{{...}}` anchors in CLAUDE.md, `policy.yml` has `bootstrap.project_type: service-desk`, audit DB row `class:bootstrap decision:RESOLVED_FINAL`. ✓
- Flag-mode: `ark create test-old --type custom --stack node-cli --deploy none --path /tmp` → still produces project, audit row `class:bootstrap decision:FLAG_OVERRIDE`. ✓
- Low-confidence: `ark create "garbled xyzzy nonsense quux"` → exit 2, `ESCALATIONS.md` gains `architectural-ambiguity` entry. ✓
- Real `~/vaults/ark/observability/policy.db` md5 unchanged before/after all tests (isolation). ✓
- `ARK_CREATE_GITHUB` unset (default) → "Skipping GitHub repo creation" message; no repo created. ✓

## Production-side-effect incident (handled)

**What:** During Plan 04-04's first smoke test (executed by gsd-executor agent), the pre-existing `gh repo create` block in `ark-create.sh` (line 799) created a real public repo at `https://github.com/goldiejz/acme-sd` because the smoke test was not GitHub-isolated.

**Root cause:** Pre-existing defect in ark-create.sh — the GitHub-creation block was unguarded. Any invocation of `ark-create.sh` end-to-end with `gh` available would create a real repo. Plan 04-04 inherited the defect; the agent correctly stopped on detection.

**Fix:** Added `ARK_CREATE_GITHUB=true` env gate around the `gh repo create` block. Default is OFF — production side-effects require explicit opt-in. Smoke tests, verifications, and isolated bootstraps no longer touch GitHub.

**Required user action:** The unauthorized repo `https://github.com/goldiejz/acme-sd` was created and could not be deleted by the agent (token lacked `delete_repo` scope). User must manually delete it via:
- `gh repo delete goldiejz/acme-sd --yes` (after granting delete_repo scope), OR
- GitHub web UI

## Deviations from plan

1. Added `ARK_CREATE_GITHUB` gate (not in original plan; necessary fix for the side-effect incident).
2. SUMMARY commit was deferred until after the incident-fix gate landed; this is the SUMMARY post-fix.

## Acceptance — all green
- bash -n passes
- 3 smoke scenarios pass
- Audit entries written for all 3 paths
- Backward compat preserved (flag-mode still works)
- No regressions in bootstrap-policy.sh (16/16) or ark-policy.sh (15/15)
