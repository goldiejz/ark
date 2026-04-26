---
phase: 06-cross-customer-learning
plan: 02
title: lesson-promoter.sh — discovery + clustering + classification core
status: complete
requirements: [REQ-AOS-31, REQ-AOS-33]
commit: e6580df
files_created:
  - scripts/lesson-promoter.sh
files_modified: []
self_test:
  assertions: 18
  passing: 18
  runtime_seconds: <2
key_decisions:
  - "Tmp file naming hashes the source path (12-char shasum prefix) so two customers' lessons.md don't collide on basename in the shared scan tmpdir"
  - "Conflict heuristic is intentionally narrow — POSITIVE imperative requires 'do '/'always' AND no negation; NEGATIVE imperative is 'don't'/'do not'/'never'/'anti-pattern'. Both kinds in same cluster across distinct customers => DEPRECATED"
  - "Apply-pending is a stub returning 0 with a TODO notice; 06-03 fills the sentinel section without git conflict"
  - "Real-data observation: 0 promote, 0 deprecate, 19 mediocre against ~/code/{strategix-crm,strategix-ioc,strategix-servicedesk}/tasks/lessons.md — confirms 06-01's finding that real cross-customer Jaccard is <60% (no spurious promotions)"
  - "Fixture lessons engineered to share most vocabulary (centralise/RBAC/role/array/source/truth/centralised/module/routes/components/import/lint/forbids/inline) to clear the 60% threshold"
---

# Phase 6 Plan 06-02: lesson-promoter.sh Summary

One-liner: Read-only cross-customer lesson promoter (discovery + clustering + classification) — 18/18 self-test assertions pass against isolated tmp portfolio; real-vault md5 invariant verified; sentinel section laid for 06-03's apply-pending body.

## Final API

```bash
# Discovery — walks $ARK_PORTFOLIO_ROOT/*/tasks/lessons.md (depth 2),
# splits each file into one tmp lesson per `## Lesson:` block.
# TSV: customer<TAB>lesson_path<TAB>title<TAB>severity
promoter_scan_lessons [root]

# Greedy single-link clustering at >=60% Jaccard similarity.
# Reads scan TSV from stdin.
# TSV: cluster_id<TAB>customer<TAB>lesson_path<TAB>title<TAB>severity<TAB>similarity_to_seed
promoter_cluster_similar

# Applies CONTEXT.md D-PROMOTION-THRESHOLD rules.
# Reads cluster TSV from stdin; emits one row per cluster.
# TSV: cluster_id<TAB>verdict<TAB>customer_count<TAB>lesson_count<TAB>route<TAB>title_seed
# verdict ∈ {PROMOTE, DEPRECATED, MEDIOCRE_KEPT_PER_CUSTOMER}
# route   ∈ {universal-patterns, anti-patterns, none}
promoter_classify_cluster

# Orchestrator: scan → cluster → classify → summary line.
# --apply hooks the (06-03-owned) promoter_apply_pending function.
# --dry-run prints the verdicts TSV instead of the summary.
promoter_run [--full | --since DATE] [--apply] [--dry-run]

# Internal helpers (not part of public contract):
#   _lp_split_file <path> <out_dir>     — split multi-lesson md by ## Lesson:
#   _lp_extract_title <lesson_file>     — strip "## Lesson:" prefix
#   _lp_infer_severity <lesson_file>    — anti / high / normal
```

CLI surface (executable mode):
```
lesson-promoter.sh test                      # 18/18 self-test
lesson-promoter.sh scan [root]               # ad-hoc discovery
lesson-promoter.sh cluster                   # ad-hoc clustering (stdin)
lesson-promoter.sh classify                  # ad-hoc classification (stdin)
lesson-promoter.sh run|--full                # default orchestrator
lesson-promoter.sh --since YYYY-MM-DD        # mtime-filtered run
lesson-promoter.sh --apply                   # stub until 06-03
lesson-promoter.sh --dry-run                 # verdicts TSV to stdout
```

## TSV row schemas (LOCKED for 06-03 to consume)

```
# Scan output (4 fields):
customer\tlesson_tmp_path\ttitle\tseverity
  severity ∈ {anti, high, normal}

# Cluster output (6 fields):
cluster_id\tcustomer\tlesson_tmp_path\ttitle\tseverity\tsimilarity_to_seed
  cluster_id    = sequential int starting at 0; cluster seed = first admitted lesson
  similarity    = 100 for self-seed; otherwise the actual similarity score (>=60)

# Classify output (6 fields, one row per cluster):
cluster_id\tverdict\tcustomer_count\tlesson_count\troute\ttitle_seed
  verdict ∈ {PROMOTE, DEPRECATED, MEDIOCRE_KEPT_PER_CUSTOMER}
  route   ∈ {universal-patterns, anti-patterns, none}
```

## Locked thresholds (CONTEXT.md D-PROMOTION-THRESHOLD)

```bash
PROMOTE_MIN_CUSTOMERS=2     # >=2 distinct customers in cluster
PROMOTE_MIN_OCCURRENCES=3   # combined lesson_count >=3
PROMOTE_MIN_SIMILARITY=60   # Jaccard percent threshold for cluster admission
```

## Conflict heuristic (the narrow guard)

A cluster is marked `DEPRECATED` (and not promoted) only if:
- `customer_count >= 2`, AND
- At least one row has POSITIVE imperative title (matches `(^| )do( |$)` or `always`, AND does NOT match `don't`/`do not`/`never`/`anti-pattern`), AND
- At least one other row has NEGATIVE imperative title (matches `don't`/`do not`/`never`/`anti-pattern`).

This is intentionally narrow per CONTEXT.md risk #3 — full conflict resolution is explicitly out of scope. The guard prevents the obvious case (one customer says "do X", another says "never do X") from auto-promoting. Self-test verifies "Anti-pattern: do not hardcode secrets" is correctly NOT misclassified — both phrases appear in the same row, so the row reads as NEG only (POS clause requires no-negation).

## Self-test results (18/18)

| #  | Assertion                                                          | Result |
|----|--------------------------------------------------------------------|--------|
| 1  | scan emits >=5 lesson rows across 3 synthetic customers            | PASS   |
| 2  | every scan row has exactly 4 tab-separated fields                  | PASS   |
| 3  | anti-pattern lesson row has severity=anti                          | PASS   |
| 4  | cust-a + cust-b RBAC lessons cluster (similarity >= 60)            | PASS   |
| 5  | RBAC cluster verdict=PROMOTE                                       | PASS   |
| 6  | RBAC cluster route=universal-patterns                              | PASS   |
| 7  | RBAC cluster customer_count=2                                      | PASS   |
| 8  | single-customer anti-pattern → MEDIOCRE_KEPT_PER_CUSTOMER          | PASS   |
| 9  | multi-customer anti-pattern (after seeding) verdict=PROMOTE        | PASS   |
| 10 | multi-customer anti-pattern route=anti-patterns                    | PASS   |
| 11 | promoter_run --dry-run emits verdicts TSV                          | PASS   |
| 12 | promoter_run --full does NOT mutate canary universal-patterns.md   | PASS   |
| 13 | real-vault $HOME/vaults/ark/lessons/universal-patterns.md md5 unchanged | PASS |
| 14 | 06-03 sentinel section open marker present                         | PASS   |
| 15 | 06-03 sentinel section close marker present                        | PASS   |
| 16 | bash-3 compat: 0 declare-A/mapfile/readarray in lib region         | PASS   |
| 17 | no `read -p` in lib region                                         | PASS   |
| 18 | VAULT_PATH redirected to tmp dir during self-test                  | PASS   |

Runtime: <2 s on macOS Bash 3.2.

## Real-vault md5 invariant

```
before: 7afcb1fcedecd4bcb11da2b7b53785d3
after:  7afcb1fcedecd4bcb11da2b7b53785d3
MD5 INVARIANT OK
```

`$HOME/vaults/ark/lessons/universal-patterns.md` is unchanged before and after running the self-test. The Phase-4 GitHub-incident lesson (real-vault writes are reserved for 06-03's apply-pending body, never the read-only discovery/cluster/classify path) is honoured.

## 06-03 sentinel section

Located at lines **293–311** of `scripts/lesson-promoter.sh`:

```
293: # === SECTION: apply-pending (Plan 06-03) ===
...
311: # === END SECTION: apply-pending ===
```

Stub `promoter_apply_pending()` returns 0 with a `# Plan 06-03 has not been applied yet — apply-pending stub` notice on stderr. 06-03 will replace the stub body in place without touching any other section.

## Real-data clustering observation (informs 06-03 threshold tuning)

Run against `~/code/strategix-crm`, `~/code/strategix-ioc`, `~/code/strategix-servicedesk`:

```
clusters: 19 (promote: 0, deprecate: 0, mediocre: 19)
```

**Every real lesson clustered alone** (`customer_count=1`, `lesson_count=1`). This confirms 06-01's empirical finding: actual cross-customer Jaccard scores are <60%, so the 60% threshold is correctly conservative — zero false-positive promotions on real data today.

Implications for 06-03:
- Apply-pending body will be a no-op against today's real lessons (no PROMOTE rows).
- This is the correct conservative posture for first-cut launch — promoter doesn't write to the universal vault until ≥2 customers genuinely converge on a similar lesson.
- Future tuning (Phase 7+) may lower the threshold OR introduce per-token weighting; for 06-02 the locked 60% is honoured.
- Test fixtures in 06-02 are intentionally engineered to cross the threshold (shared vocabulary in title + rule body) so the classification logic is exercised; real lessons are too vocabulary-divergent to cluster today.

## Constraints honoured

- **Bash 3 compat:** Indexed arrays only (`seed_paths[$i]=…`, no associative); no `mapfile` / `readarray`; no `${var,,}`. Path hashing via `shasum` with `md5 -q` fallback.
- **Sourceable:** `set -uo pipefail` only — no `set -e`. Verified via `source scripts/lesson-promoter.sh; type promoter_scan_lessons` returns function definition.
- **No real-vault writes:** Self-test redirects `$VAULT_PATH`, `$ARK_HOME`, `$UNIVERSAL_TARGET`, `$ANTIPATTERN_TARGET` to `mktemp -d`; canary file md5 invariant verified inside test, real-vault md5 invariant verified outside test.
- **No `read -p`:** Verified by self-test (assertion 17, comment-skip discipline).
- **Audit discipline (Phase 2 contract):** No `_policy_log` calls in this module — apply step is the audit boundary, owned by 06-03. The sentinel section comment explicitly documents this for 06-03.
- **No external HTTP, no ML, no Bash-4 features.**

## Confirmation

- REQ-AOS-31 (cross-customer lesson promotion infrastructure): discovery + clustering + classification primitives delivered; apply step deferred to 06-03 by design.
- REQ-AOS-33 (anti-pattern routing): severity=anti causes route=anti-patterns when PROMOTE threshold is met; verified by self-test assertion 10.
- 06-03 sentinel section present and correctly named: verified by self-test assertions 14, 15.

## Verification commands

```bash
bash scripts/lesson-promoter.sh test                  # 18/18 PASS
bash -n scripts/lesson-promoter.sh                    # syntax OK
bash -c 'source scripts/lesson-promoter.sh; type promoter_scan_lessons'   # function
ARK_PORTFOLIO_ROOT=$HOME/code bash scripts/lesson-promoter.sh --dry-run   # real-data dry run
md5 -q $HOME/vaults/ark/lessons/universal-patterns.md                     # unchanged
```

## Self-Check: PASSED

- File exists: `scripts/lesson-promoter.sh` (672 lines, executable)
- Commit: `e6580df` (Phase 6 Plan 06-02: lesson-promoter.sh — discovery + clustering + classification)
- Self-test: 18/18 assertions pass
- Sourceable: confirmed (functions resolve)
- Real-vault md5 invariant: confirmed (7afcb1fc... before == after)
- 06-03 sentinel section: lines 293–311
