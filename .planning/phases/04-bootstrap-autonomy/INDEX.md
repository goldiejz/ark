# Phase 04 — AOS: Bootstrap Autonomy — Plan Index

This phase is split into 8 plans across 6 waves. Wave-1 builds the inference foundation
(`bootstrap-policy.sh`). Wave 2 fans out template tagging + CLAUDE.md base template (no
file conflicts — both are pure data). Waves 3-6 wire and verify.

| Plan   | Title                                                                                | Wave | Depends on            | Files modified |
|--------|--------------------------------------------------------------------------------------|------|-----------------------|----------------|
| 04-01  | bootstrap-policy.sh — inference engine + cascading customer config + self-test       | 1    | —                     | scripts/bootstrap-policy.sh, scripts/lib/bootstrap-customer.sh |
| 04-02  | project-types/*.md — keyword frontmatter + default-stack/deploy machine-readable     | 2    | 04-01                 | bootstrap/project-types/service-desk-template.md, bootstrap/project-types/revops-template.md, bootstrap/project-types/ops-intelligence-template.md, bootstrap/project-types/custom-template.md |
| 04-03  | claude-md-template.md — base + addendum anchors + customer footer slot               | 2    | 04-01                 | bootstrap/claude-md-template.md, bootstrap/claude-md-addendum/service-desk.md, bootstrap/claude-md-addendum/revops.md, bootstrap/claude-md-addendum/ops-intelligence.md, bootstrap/claude-md-addendum/custom.md |
| 04-04  | ark-create.sh — wire bootstrap_classify; description path; preserve flag path; atomic | 3    | 04-01, 04-02, 04-03   | scripts/ark-create.sh |
| 04-05  | Customer policy.yml resolution + customer dir creation (mkdir-lock)                  | 3    | 04-01                 | scripts/lib/bootstrap-customer.sh, scripts/lib/policy-config.sh |
| 04-06  | ark dispatcher — extend `ark create` help; description-arg path                      | 4    | 04-04                 | scripts/ark |
| 04-07  | Tier 10 verify — 5-fixture synthetic test; isolated tmp vault; regression check      | 5    | 04-04, 04-05, 04-06   | scripts/ark-verify.sh |
| 04-08  | STRUCTURE.md AOS Bootstrap Contract; REQ-AOS-15..22; STATE.md Phase 4 close          | 6    | 04-07                 | STRUCTURE.md (or vault equivalent), .planning/REQUIREMENTS.md, .planning/STATE.md, SKILL.md (best-effort) |

## Wave structure

- **Wave 1:** 04-01 (inference engine — every other plan sources it)
- **Wave 2:** 04-02, 04-03 (parallel — disjoint files; both consumed by 04-04)
- **Wave 3:** 04-04, 04-05 (parallel — different files; 04-04 wires the engine, 04-05 finalizes the customer-config layer in policy-config.sh)
- **Wave 4:** 04-06 (dispatcher; needs 04-04 description-path live)
- **Wave 5:** 04-07 (Tier 10 verify; needs all wiring done)
- **Wave 6:** 04-08 (docs)

## Wave-2 file-conflict note

04-02 and 04-03 modify disjoint paths (`bootstrap/project-types/` vs `bootstrap/claude-md-template.md` + `bootstrap/claude-md-addendum/`) so they're safely parallel.

## Wave-3 file-conflict note

04-04 modifies `scripts/ark-create.sh`. 04-05 modifies `scripts/lib/bootstrap-customer.sh` (created stub in 04-01) + appends a customer-layer hook to `scripts/lib/policy-config.sh`. No overlap.

## Requirements coverage

REQ-AOS-15..REQ-AOS-22 map 1:1 to the 8 Phase 4 acceptance criteria in CONTEXT.md.
IDs are minted in plan frontmatter; rows added to `.planning/REQUIREMENTS.md` by 04-08.

| Req | Statement | Covered by |
|-----|-----------|------------|
| REQ-AOS-15 | scripts/bootstrap-policy.sh exists; sourceable; self-test passes | 04-01 |
| REQ-AOS-16 | `ark create "<description>" --customer <name>` runs to completion with zero prompts | 04-04, 04-06 |
| REQ-AOS-17 | Inferred type/stack/deploy logged via `_policy_log "bootstrap" ...` with full context | 04-01, 04-04 |
| REQ-AOS-18 | Per-project `.planning/policy.yml` auto-generated with inferred values | 04-04 |
| REQ-AOS-19 | CLAUDE.md atomically written from base + project-type addendum + customer footer | 04-03, 04-04 |
| REQ-AOS-20 | Existing `ark create` flag-based invocation still works (backward compat) | 04-04, 04-06 |
| REQ-AOS-21 | Tier 10 verify: 5 different project types, no prompts, all produce valid scaffolds | 04-07 |
| REQ-AOS-22 | Existing Tier 1–9 still pass (no regression) | 04-07 |

## Phase 2/3 lessons honored (avoid regression)

- **Single audit writer:** All bootstrap audit-log entries go through `_policy_log` from `ark-policy.sh`. Bootstrap classifier sources ark-policy.sh and calls `_policy_log "bootstrap" ...`; never inline INSERTs. Mirrors Phase 2 NEW-B-2 + Phase 3 single-writer rule.
- **Bash 3 compat (macOS):** No `declare -A`, no `${var,,}` lowercasing — use `tr '[:upper:]' '[:lower:]'`. Single-quoted heredocs for any embedded Python (none expected — Phase 4 is pure bash + awk).
- **Isolated test vaults:** Tier 10 follows NEW-W-1 — `mktemp -d`, copy scripts, run against `ARK_HOME=$TMP_VAULT` and `--path "$TMP_PROJECTS"`, never touch real `~/code/` or real audit DB. Real DB md5 captured before/after; assertion that md5 unchanged.
- **No `read -p` in bootstrap-path:** 04-04 strips any `read -p` from `ark-create.sh`; 04-07 includes a regression check (`grep -nE 'read[[:space:]]+-p' scripts/ark-create.sh | grep -v '# AOS: intentional gate'` returns 0).
- **Atomic file writes:** CLAUDE.md, policy.yml, package.json all written via `tmp + mv` pattern (write to `$file.tmp`, then `mv $file.tmp $file`). Never partial state.
- **Concurrency safety:** 04-05 uses `mkdir`-lock for customer-dir creation (POSIX-atomic; no `flock` dependency on macOS).

## Locked decisions from CONTEXT.md (verbatim — do not revisit)

- **D-INFER:** Heuristic keyword-overlap scoring against `project-types/*.md` (no ML, no embeddings). Confidence ≥ 50% → confident; below → escalate `architectural-ambiguity`.
- **D-STACK:** Project-type template declares default stack; env or `policy.yml bootstrap.stack_override` overrides.
- **D-DEPLOY:** service-desk/revops/ops-intelligence → cloudflare; custom/scratch → none. Customer-policy can override.
- **D-CUSTOMER:** Parse `for <name>` from description; missing → `scratch`. Customer dir auto-created via mkdir-lock; idempotent.
- **D-PROJ-POLICY:** `<project>/.planning/policy.yml` auto-generated; consumed by Phase 2's existing cascading config.
- **D-CLAUDE-MD:** base template + project-type addendum + customer footer; atomic write; never overwrite an existing CLAUDE.md (destructive op → ESCALATIONS).
- **D-AUDIT:** Every bootstrap decision audit-logged via `_policy_log "bootstrap" "<DECISION>" "<reason>" "<context_json>"`. Class taxonomy: `bootstrap` and `escalation`.
- **D-COMPAT:** Existing flag-based `ark create <name> --type X --stack Y --deploy Z --customer C` continues to work. Phase 4 only ADDS the description-based path; flags still override inference.
