# Phase 06 — AOS: Cross-Customer Learning Autonomy — Plan Index

This phase is split into 6 plans across 5 waves. Wave-1 builds the similarity
primitive (`scripts/lib/lesson-similarity.sh`). Wave-2 builds the discovery +
clustering core (`scripts/lesson-promoter.sh::promoter_scan_lessons`,
`promoter_cluster_similar`, `promoter_classify_cluster`). Wave-3 fans out into
two parallel extensions (apply-pending writer + audit, and ark dispatcher
wiring). Wave-4 verifies via Tier 12. Wave-5 mints requirements and updates
docs.

| Plan   | Title                                                                         | Wave | Depends on    | Files modified |
|--------|-------------------------------------------------------------------------------|------|---------------|----------------|
| 06-01  | scripts/lib/lesson-similarity.sh — Jaccard token-overlap; sourceable; self-test | 1   | —             | scripts/lib/lesson-similarity.sh |
| 06-02  | scripts/lesson-promoter.sh — discovery + clustering + classification + self-test | 2   | 06-01         | scripts/lesson-promoter.sh |
| 06-03  | promoter_apply_pending — atomic write + git commit + _policy_log audit         | 3   | 06-02         | scripts/lesson-promoter.sh (in-place section), ~/vaults/ark/lessons/universal-patterns.md (managed), ~/vaults/ark/bootstrap/anti-patterns.md (managed) |
| 06-04  | ark promote-lessons subcommand + post-phase trigger in ark-deliver.sh           | 3   | 06-02         | scripts/ark, scripts/ark-deliver.sh |
| 06-05  | Tier 12 verify suite — synthetic 3-customer fixture                            | 4   | 06-03, 06-04  | scripts/ark-verify.sh |
| 06-06  | STRUCTURE.md AOS Phase 6 contract; REQ-AOS-31..39; STATE.md + ROADMAP.md + SKILL.md | 5 | 06-05         | STRUCTURE.md (or vault equivalent), .planning/REQUIREMENTS.md, .planning/STATE.md, .planning/ROADMAP.md, SKILL.md (best-effort) |

## Wave structure

- **Wave 1:** 06-01 (similarity primitive — every other plan consumes it).
- **Wave 2:** 06-02 (discovery + clustering + classification core; lays sentinel
  section for Plan 06-03's apply-pending body).
- **Wave 3:** 06-03 + 06-04 in parallel.
  - 06-03 owns the `# === SECTION: apply-pending (Plan 06-03) ===` region of
    `scripts/lesson-promoter.sh` plus the two managed vault files
    (universal-patterns.md, anti-patterns.md).
  - 06-04 touches `scripts/ark` (new dispatcher case) and `scripts/ark-deliver.sh`
    (post-phase non-fatal trigger). Disjoint files from 06-03 → no conflict.
- **Wave 4:** 06-05 (Tier 12 verify; needs full pipeline live).
- **Wave 5:** 06-06 (docs + requirement minting).

## Wave-3 file-conflict note

06-03 and 06-04 are runnable in parallel:
- 06-03 modifies `scripts/lesson-promoter.sh` only inside the
  `# === SECTION: apply-pending (Plan 06-03) ===` … `# === END SECTION ===`
  region laid down by 06-02, and writes to vault files `universal-patterns.md`
  and `anti-patterns.md` (managed sections only).
- 06-04 modifies `scripts/ark` (dispatcher case statement — new `promote-lessons`
  arm + help text) and `scripts/ark-deliver.sh` (single new post-phase hook).
- No overlapping files. Wave-3 fan-out is safe.

## Requirements coverage

REQ-AOS-31..REQ-AOS-39 map 1:1 to the 9 Phase 6 acceptance criteria in
CONTEXT.md. IDs are minted in plan frontmatter; rows added to
`.planning/REQUIREMENTS.md` by 06-06.

| Req         | Statement | Covered by |
|-------------|-----------|------------|
| REQ-AOS-31  | scripts/lesson-promoter.sh exists; sourceable; self-test passes | 06-02 |
| REQ-AOS-32  | scripts/lib/lesson-similarity.sh exposes `lesson_similarity <a> <b>` returning 0..100 | 06-01 |
| REQ-AOS-33  | Walking $ARK_PORTFOLIO_ROOT/*/tasks/lessons.md produces a candidate set | 06-02 |
| REQ-AOS-34  | Patterns ≥2 customers + ≥60% similarity → auto-promoted to ~/vaults/ark/lessons/universal-patterns.md | 06-03 |
| REQ-AOS-35  | Anti-patterns auto-promoted to ~/vaults/ark/bootstrap/anti-patterns.md | 06-03 |
| REQ-AOS-36  | Every promotion audit-logged via `_policy_log "lesson_promote" "PROMOTED" ...` | 06-03 |
| REQ-AOS-37  | `ark promote-lessons` subcommand exists (manual run, --full or --since) | 06-04 |
| REQ-AOS-38  | Tier 12 verify: synthetic 3-customer fixture asserts correct promotion | 06-05 |
| REQ-AOS-39  | Existing Tier 1–11 still pass (no regression) | 06-05 |

## Phase 2/3/4/5 lessons honored (avoid regression)

- **Single audit writer:** All `lesson_promote` class entries go through
  `_policy_log` from `ark-policy.sh`. No inline `INSERT INTO decisions`.
  Mirrors Phase 2 NEW-B-2 + Phase 3 single-writer rule.
- **Bash 3 compat (macOS):** No `declare -A`, no `mapfile`, no `${var,,}`. Use
  `tr` for case folds, `awk` for parsing and integer-percent math, `sort -u`
  for dedup-by-line.
- **No `read -p` in delivery-path:** 06-04's post-phase hook is non-interactive
  and non-fatal. 06-05 includes a regression check (`grep -nE 'read -p'`
  against the delivery-path scripts).
- **Atomic file writes:** `universal-patterns.md` and `anti-patterns.md`
  patches go through `tmp + mv`. mkdir-lock around vault writes for concurrency
  safety (mirrors Phase 3 03-03's `_lrn_acquire_lock` pattern).
- **Phase-4 GitHub-incident lesson:** Tier 12 fixture MUST NOT touch real
  `~/code/`, real `~/vaults/ark/lessons/`, real `~/vaults/ark/bootstrap/`, or
  invoke `gh repo create`. Use `mktemp -d` for portfolio root and vault root;
  set `ARK_PORTFOLIO_ROOT=$TMP_PORTFOLIO`, `ARK_HOME=$TMP_VAULT`. Real-vault
  write attempt is a test failure. Real DB md5 captured before/after; assertion
  that md5 unchanged.
- **Self-referential test pattern trap (Phase 4 lesson):** the `read -p`
  regression check in 06-05 must skip the test/comment lines themselves
  (use `grep -v '^[[:space:]]*#'` and exclude the verify-suite's own region
  by line range or marker).
- **Idempotency:** re-running over same data ⇒ no new commits, no duplicate
  entries. Implementation: idempotency check via grep of canonical pattern
  marker before append in apply-pending.
- **Backward compat:** existing per-customer `tasks/lessons.md` files are
  read-only inputs; promotion is additive — never modifies or deletes
  per-customer lessons (per CONTEXT.md "Out of scope").

## Locked decisions from CONTEXT.md (verbatim — do not revisit)

- **D-LESSON-SCOPE:** Lessons discovered by walking
  `${ARK_PORTFOLIO_ROOT:-$HOME/code}/*/tasks/lessons.md`. Each customer project
  has its own file per project-standard.md.
- **D-LESSON-EXTRACT:** Per lesson, extract title (first heading after
  `## Lesson:` or first `^# `), severity (frontmatter or inferred), scope tags,
  rule body. Heuristic — no ML.
- **D-SIMILARITY:** Jaccard token-overlap on (title + rule body) tokens
  (lowercased, alphanumerics only, stop-words removed). Returns integer 0..100.
- **D-PROMOTION-THRESHOLD:** ≥2 distinct customers + ≥60% similarity. Combined
  occurrence count ≥3 (e.g., 1 in customer A + 2 in customer B).
- **D-ANTI-PATTERN-DETECT:** Title contains the literal substrings
  `anti-pattern` or `don't` (case-insensitive) → routes to
  `~/vaults/ark/bootstrap/anti-patterns.md`. Otherwise routes to
  `~/vaults/ark/lessons/universal-patterns.md`.
- **D-AUDIT-CLASS:** All promotions logged via
  `_policy_log "lesson_promote" "<DECISION>" ...`. Decisions:
  `PROMOTED | DEPRECATED | MEDIOCRE_KEPT_PER_CUSTOMER`.
- **D-CADENCE:** Triggered post-phase by ark-deliver.sh (mirrors Phase 3 hook),
  also manually via `ark promote-lessons [--full | --since DATE]`.
- **D-IDEMPOTENT:** Re-running over same data produces no new commits and no
  duplicate entries. Idempotency enforced via canonical marker grep before
  append.
- **D-NO-DEPRECATE-CUSTOMER:** Per-customer `tasks/lessons.md` is never
  modified by the promoter (additive only). Phase 6 PROMOTES; per-customer
  lessons stay.
- **D-NO-ML:** Heuristic similarity only — no embeddings, no transformers,
  no external HTTP calls.
