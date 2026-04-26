#!/usr/bin/env bash
# lesson-promoter.sh — Cross-customer lesson discovery + clustering + classification.
#
# Phase 6 Plans 06-02 (this) and 06-03 (apply-pending sentinel section).
# Requirements: REQ-AOS-31 (cross-customer lesson promotion), REQ-AOS-33
# (anti-pattern routing).
#
# READ-ONLY against per-customer tasks/lessons.md files at this stage.
# Vault writes are confined to the apply-pending sentinel section (filled
# by Plan 06-03). No `_policy_log` calls in 06-02 — apply step is the
# audit boundary (Phase 2 single-writer contract).
#
# Public API:
#   promoter_scan_lessons [root]    — TSV: customer<TAB>lesson_path<TAB>title<TAB>severity
#   promoter_cluster_similar        — TSV: cluster_id<TAB>customer<TAB>lesson_path<TAB>title<TAB>severity<TAB>similarity
#   promoter_classify_cluster       — TSV: cluster_id<TAB>verdict<TAB>customer_count<TAB>lesson_count<TAB>route<TAB>title_seed
#   promoter_run [--full|--since DATE] [--apply] [--dry-run]
#
# Bash 3 compat (macOS default). NO `declare -A`, `mapfile`, `readarray`.
# NOT `set -e` (sourceable lib must not break callers).

set -uo pipefail

# Locate sibling lib dir (works whether sourced or executed directly)
_LP_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/lib"

# Source similarity primitive (06-01)
# shellcheck disable=SC1091
if [[ -f "$_LP_LIB_DIR/lesson-similarity.sh" ]]; then
  source "$_LP_LIB_DIR/lesson-similarity.sh"
else
  echo "❌ lesson-promoter.sh requires scripts/lib/lesson-similarity.sh (Plan 06-01)" >&2
  exit 1
fi

# === Locked thresholds (CONTEXT.md D-PROMOTION-THRESHOLD) ===
PROMOTE_MIN_CUSTOMERS=2
PROMOTE_MIN_OCCURRENCES=3
PROMOTE_MIN_SIMILARITY=60

# === Roots and targets ===
ARK_PORTFOLIO_ROOT="${ARK_PORTFOLIO_ROOT:-$HOME/code}"
VAULT_PATH="${ARK_HOME:-$HOME/vaults/ark}"
UNIVERSAL_TARGET="${UNIVERSAL_TARGET:-$VAULT_PATH/lessons/universal-patterns.md}"
ANTIPATTERN_TARGET="${ANTIPATTERN_TARGET:-$VAULT_PATH/bootstrap/anti-patterns.md}"

# === _lp_split_file <path> <out_dir> ===
# Split a multi-lesson tasks/lessons.md into one tmp file per `## Lesson:` block.
# For files without `## Lesson:`, treat the whole file as a single lesson.
# Echoes each emitted tmp path on stdout.
_lp_split_file() {
  local file="$1"
  local out_dir="$2"
  local base
  # Use a hash of the source path so two customers' lessons.md files don't
  # collide on basename in the shared scan tmpdir.
  local path_hash
  path_hash=$(printf '%s' "$file" | shasum 2>/dev/null | cut -c1-12)
  if [[ -z "$path_hash" ]]; then
    path_hash=$(printf '%s' "$file" | md5 -q 2>/dev/null | cut -c1-12)
  fi
  base="$(basename "$file" .md)-$path_hash"

  if [[ ! -f "$file" ]] || [[ ! -s "$file" ]]; then
    return 0
  fi

  # Detect Format A (## Lesson: ...) blocks
  if grep -qi '^## lesson:' "$file" 2>/dev/null; then
    awk -v out_dir="$out_dir" -v base="$base" '
      BEGIN { idx = 0; current = "" }
      tolower($0) ~ /^## lesson:/ {
        if (current != "") {
          fname = out_dir "/" base "-" idx ".md"
          print current > fname
          close(fname)
          print fname
          idx++
        }
        current = $0 "\n"
        next
      }
      # Next ## (non-Lesson) heading closes block too
      current != "" && /^## / && tolower($0) !~ /^## lesson:/ {
        fname = out_dir "/" base "-" idx ".md"
        print current > fname
        close(fname)
        print fname
        idx++
        current = ""
        next
      }
      current != "" { current = current $0 "\n"; next }
      END {
        if (current != "") {
          fname = out_dir "/" base "-" idx ".md"
          print current > fname
          close(fname)
          print fname
        }
      }
    ' "$file"
    return 0
  fi

  # Format B / fallback: whole file as single lesson
  local fname="$out_dir/$base-0.md"
  cp "$file" "$fname"
  echo "$fname"
}

# === _lp_infer_severity <lesson_file> ===
# anti  → title or body contains 'anti-pattern' or "don't" / "do not"
# high  → contains WARNING|CRITICAL|MUST
# normal → default
_lp_infer_severity() {
  local file="$1"
  if grep -qiE "anti-pattern|don't|do not" "$file" 2>/dev/null; then
    echo "anti"
    return 0
  fi
  if grep -qE "WARNING|CRITICAL|MUST" "$file" 2>/dev/null; then
    echo "high"
    return 0
  fi
  echo "normal"
}

# === _lp_extract_title <lesson_file> ===
# Strip "## Lesson:" prefix from first heading; fallback to first "# " heading.
_lp_extract_title() {
  local file="$1"
  local title
  title=$(grep -i '^## lesson:' "$file" 2>/dev/null | head -1 \
    | sed -E 's/^##[[:space:]]*[Ll][Ee][Ss][Ss][Oo][Nn]:[[:space:]]*//')
  if [[ -n "$title" ]]; then
    echo "$title"
    return 0
  fi
  title=$(grep '^# ' "$file" 2>/dev/null | head -1 | sed -E 's/^#[[:space:]]+//')
  if [[ -n "$title" ]]; then
    echo "$title"
    return 0
  fi
  echo "(untitled)"
}

# === promoter_scan_lessons [root] ===
# Walks <root>/*/tasks/lessons.md (depth 2 — never recurse into project subtrees).
# Splits each file into one lesson per tmp path. Emits TSV rows:
#   customer<TAB>lesson_path<TAB>title<TAB>severity
# Tmp output directory survives until caller cleans up (orchestrator has trap).
promoter_scan_lessons() {
  local root="${1:-$ARK_PORTFOLIO_ROOT}"
  local since_epoch="${LP_SINCE_EPOCH:-0}"
  local out_dir
  out_dir=$(mktemp -d -t ark-lesson-scan-XXXXXXXX)
  # Export for orchestrator cleanup
  export LP_LAST_SCAN_TMPDIR="$out_dir"

  if [[ ! -d "$root" ]]; then
    return 0
  fi

  local lesson_file customer customer_dir lesson_path title severity mtime
  for lesson_file in "$root"/*/tasks/lessons.md; do
    [[ -f "$lesson_file" ]] || continue
    if [[ "$since_epoch" -gt 0 ]]; then
      mtime=$(stat -f %m "$lesson_file" 2>/dev/null || stat -c %Y "$lesson_file" 2>/dev/null || echo 0)
      [[ "$mtime" -lt "$since_epoch" ]] && continue
    fi
    customer_dir=$(dirname "$(dirname "$lesson_file")")
    customer=$(basename "$customer_dir")

    # Split and iterate
    while IFS= read -r lesson_path; do
      [[ -z "$lesson_path" ]] && continue
      [[ -f "$lesson_path" ]] || continue
      title=$(_lp_extract_title "$lesson_path")
      severity=$(_lp_infer_severity "$lesson_path")
      printf '%s\t%s\t%s\t%s\n' "$customer" "$lesson_path" "$title" "$severity"
    done < <(_lp_split_file "$lesson_file" "$out_dir")
  done
}

# === promoter_cluster_similar ===
# Reads scan TSV from stdin, applies greedy single-link clustering against
# cluster seeds. Threshold = $PROMOTE_MIN_SIMILARITY (60).
# Emits TSV: cluster_id<TAB>customer<TAB>lesson_path<TAB>title<TAB>severity<TAB>similarity_to_seed
promoter_cluster_similar() {
  local line customer lesson_path title severity
  # Bash-3-compat: parallel indexed arrays (no associative)
  local -a seed_paths
  seed_paths=()
  local seed_count=0
  local i sim assigned cluster_id

  while IFS=$'\t' read -r customer lesson_path title severity; do
    [[ -z "$lesson_path" ]] && continue
    assigned=-1
    sim=100
    i=0
    while [[ "$i" -lt "$seed_count" ]]; do
      sim=$(lesson_similarity "$lesson_path" "${seed_paths[$i]}" 2>/dev/null)
      sim="${sim:-0}"
      if [[ "$sim" -ge "$PROMOTE_MIN_SIMILARITY" ]]; then
        assigned="$i"
        break
      fi
      i=$((i + 1))
    done
    if [[ "$assigned" -ge 0 ]]; then
      cluster_id="$assigned"
    else
      cluster_id="$seed_count"
      seed_paths[$seed_count]="$lesson_path"
      seed_count=$((seed_count + 1))
      sim=100
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$cluster_id" "$customer" "$lesson_path" "$title" "$severity" "$sim"
  done
}

# === promoter_classify_cluster ===
# Reads cluster TSV from stdin, emits one row per cluster:
#   cluster_id<TAB>verdict<TAB>customer_count<TAB>lesson_count<TAB>route<TAB>title_seed
# verdict ∈ {PROMOTE, DEPRECATED, MEDIOCRE_KEPT_PER_CUSTOMER}
# route   ∈ {universal-patterns, anti-patterns, none}
promoter_classify_cluster() {
  # Stage stdin to a tmp file so we can re-scan per cluster
  local stage
  stage=$(mktemp -t ark-cluster-stage-XXXXXXXX)
  cat > "$stage"

  if [[ ! -s "$stage" ]]; then
    rm -f "$stage"
    return 0
  fi

  # Get unique cluster IDs in order of first appearance
  local cluster_ids
  cluster_ids=$(awk -F'\t' '!seen[$1]++ { print $1 }' "$stage")

  local cid customer_count lesson_count title_seed has_anti has_do has_dont route verdict
  while IFS= read -r cid; do
    [[ -z "$cid" ]] && continue
    # Subset for this cluster
    customer_count=$(awk -F'\t' -v c="$cid" '$1==c { print $2 }' "$stage" | sort -u | wc -l | tr -d ' ')
    lesson_count=$(awk -F'\t' -v c="$cid" '$1==c' "$stage" | wc -l | tr -d ' ')
    title_seed=$(awk -F'\t' -v c="$cid" '$1==c { print $4; exit }' "$stage")
    has_anti=$(awk -F'\t' -v c="$cid" '$1==c && $5=="anti"' "$stage" | wc -l | tr -d ' ')

    # Conflict heuristic (intentionally narrow — a guard, not a resolver):
    # A row has POSITIVE imperative if its title contains "do " or "always"
    # but does NOT also contain a negation ("don't", "do not", "never",
    # "anti-pattern"). A row has NEGATIVE imperative if its title contains
    # "don't" / "do not" / "never" / "anti-pattern". Conflict = both kinds
    # present in the same cluster across distinct customers.
    has_do=$(awk -F'\t' -v c="$cid" '$1==c { t=tolower($4);
        is_neg = (t ~ /don'\''?t|do not|never|anti-pattern/);
        is_pos = (t ~ /(^| )do( |$)|always/);
        if (is_pos && !is_neg) print "POS"
      }' "$stage" | grep -c POS || true)
    has_dont=$(awk -F'\t' -v c="$cid" '$1==c { t=tolower($4);
        if (t ~ /don'\''?t|do not|never|anti-pattern/) print "NEG"
      }' "$stage" | grep -c NEG || true)
    has_do=$(echo "$has_do" | tr -d ' \n')
    has_dont=$(echo "$has_dont" | tr -d ' \n')

    if [[ "$customer_count" -ge 2 ]] && [[ "$has_do" -ge 1 ]] && [[ "$has_dont" -ge 1 ]]; then
      verdict="DEPRECATED"
      route="none"
    elif [[ "$customer_count" -ge "$PROMOTE_MIN_CUSTOMERS" ]] && [[ "$lesson_count" -ge "$PROMOTE_MIN_OCCURRENCES" ]]; then
      verdict="PROMOTE"
      if [[ "$has_anti" -ge 1 ]]; then
        route="anti-patterns"
      else
        route="universal-patterns"
      fi
    else
      verdict="MEDIOCRE_KEPT_PER_CUSTOMER"
      route="none"
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$cid" "$verdict" "$customer_count" "$lesson_count" "$route" "$title_seed"
  done <<< "$cluster_ids"

  rm -f "$stage"
}

# === SECTION: apply-pending (Plan 06-03) ===
# Plan 06-03: promoter_apply_pending — atomic write + git commit + audit + idempotency.
# Reads a verdicts TSV (one cluster per line) emitted by promoter_classify_cluster:
#   cluster_id<TAB>verdict<TAB>customer_count<TAB>lesson_count<TAB>route<TAB>title_seed
#
# For PROMOTE: atomically appends a managed block to $UNIVERSAL_TARGET or
# $ANTIPATTERN_TARGET under mkdir-lock at $VAULT_PATH/.lesson-promoter.lock,
# emits one `_policy_log "lesson_promote" "PROMOTED" ...` audit row,
# and commits the touched file in vault git.
#
# For DEPRECATED (conflict cluster): audit-only, no file write, decision=DEPRECATED.
# For MEDIOCRE_KEPT_PER_CUSTOMER: audit-only when LESSON_AUDIT_MEDIOCRE=1; else silent.
#
# Idempotent: per-cluster canonical marker is grepped (literal-string -F) in
# the target before append. Re-running the same verdicts produces no new
# appends, no new audit rows, no new commits.
#
# Concurrency-safe: mkdir-lock serialises parallel invocations.
# Atomic: tmp+mv only; no in-place edits.
# Returns: 0 on success (any number applied including zero), 1 on lock failure.

# Source ark-policy.sh for _policy_log (single audit writer). ark-policy.sh's
# tail block triggers a self-test when sourced with $1=test. Shield by saving
# + clearing $@, sourcing, then restoring.
_LP_SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
if [[ -z "${_LP_POLICY_SOURCED:-}" ]] && [[ -f "$_LP_SCRIPTS_DIR/ark-policy.sh" ]]; then
  if ! type _policy_log >/dev/null 2>&1; then
    _LP_SAVED_ARGS=("$@")
    set -- _lp_noop_arg
    # shellcheck disable=SC1091
    source "$_LP_SCRIPTS_DIR/ark-policy.sh" >/dev/null 2>&1 || true
    if [[ "${#_LP_SAVED_ARGS[@]}" -gt 0 ]]; then
      set -- "${_LP_SAVED_ARGS[@]}"
    else
      set --
    fi
    unset _LP_SAVED_ARGS
  fi
  _LP_POLICY_SOURCED=1
fi

# === Lock helpers (mkdir is atomic on POSIX; macOS-safe) ===
_lp_acquire_lock() {
  local lock="$1"
  local timeout="${2:-30}"
  local i=0
  while ! mkdir "$lock" 2>/dev/null; do
    i=$(( i + 1 ))
    if [[ $i -ge $timeout ]]; then
      return 1
    fi
    sleep 1
  done
  echo "$$" > "$lock/pid" 2>/dev/null || true
  return 0
}

_lp_release_lock() {
  local lock="$1"
  rm -f "$lock/pid" 2>/dev/null || true
  rmdir "$lock" 2>/dev/null || true
}

# === _lp_slug "<title>" ===
# Lowercase, non-alphanumerics → '-', collapse runs, trim, truncate 60.
_lp_slug() {
  echo "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | tr -c 'a-z0-9' '-' \
    | sed -E 's/-+/-/g; s/^-//; s/-$//' \
    | cut -c1-60
}

# === _lp_init_target_if_missing <path> <header> ===
# Atomically writes a one-time managed-section header if the file is missing
# OR present-but-empty. Never overwrites existing content.
_lp_init_target_if_missing() {
  local target="$1"
  local header="$2"
  if [[ -s "$target" ]]; then
    return 0
  fi
  mkdir -p "$(dirname "$target")"
  local tmp="${target}.tmp.$$"
  {
    echo "# $header"
    echo ""
    echo "<!-- AOS Phase 6 — auto-promoted: managed section. Manual entries above this line are preserved; auto-promoted blocks are appended below by scripts/lesson-promoter.sh. -->"
    echo ""
  } > "$tmp"
  mv "$tmp" "$target"
}

# === _lp_customers_for <cluster_id> ===
# Reads $LP_CLUSTER_TSV (cluster TSV from promoter_cluster_similar) and emits
# a comma-separated unique customer list for the given cluster_id. Degrades
# to "(unknown)" if the env var is not set.
_lp_customers_for() {
  local cid="$1"
  if [[ -z "${LP_CLUSTER_TSV:-}" ]] || [[ ! -f "$LP_CLUSTER_TSV" ]]; then
    echo "(unknown)"
    return 0
  fi
  local list
  list=$(awk -F'\t' -v c="$cid" '$1==c { print $2 }' "$LP_CLUSTER_TSV" \
    | sort -u | tr '\n' ',' | sed -E 's/,$//; s/,/, /g')
  if [[ -z "$list" ]]; then
    echo "(unknown)"
  else
    echo "$list"
  fi
}

# === _lp_seed_body_for <cluster_id> ===
# Emits the rule body of the seed lesson (first row in cluster TSV for that
# cluster_id). Degrades to a placeholder if the path is missing.
_lp_seed_body_for() {
  local cid="$1"
  if [[ -z "${LP_CLUSTER_TSV:-}" ]] || [[ ! -f "$LP_CLUSTER_TSV" ]]; then
    echo "_(seed body not available — LP_CLUSTER_TSV not set)_"
    return 0
  fi
  local seed_path
  seed_path=$(awk -F'\t' -v c="$cid" '$1==c { print $3; exit }' "$LP_CLUSTER_TSV")
  if [[ -z "$seed_path" ]] || [[ ! -f "$seed_path" ]]; then
    echo "_(seed body not available)_"
    return 0
  fi
  # Strip the leading "## Lesson:" heading if present (already in our title).
  awk 'NR==1 && tolower($0) ~ /^## lesson:/ { next } { print }' "$seed_path"
}

# === _lp_citations_for <cluster_id> ===
# One bullet per source lesson in the cluster, formatted "- <customer>: <relpath>".
_lp_citations_for() {
  local cid="$1"
  if [[ -z "${LP_CLUSTER_TSV:-}" ]] || [[ ! -f "$LP_CLUSTER_TSV" ]]; then
    echo "- (citations not available — LP_CLUSTER_TSV not set)"
    return 0
  fi
  awk -F'\t' -v c="$cid" -v root="${ARK_PORTFOLIO_ROOT:-}" '
    $1==c {
      cust=$2; path=$3;
      # Best-effort relative path (strip portfolio root prefix if present)
      rel=path;
      if (root != "" && index(path, root) == 1) {
        rel=substr(path, length(root)+2);
      }
      printf "- %s: %s\n", cust, rel
    }
  ' "$LP_CLUSTER_TSV"
}

# === Public: promoter_apply_pending <verdicts_tsv_file> ===
promoter_apply_pending() {
  local verdicts="${1:?usage: promoter_apply_pending <verdicts_tsv_file>}"
  if [[ ! -s "$verdicts" ]]; then
    echo "applied: 0 (no verdicts at $verdicts)"
    return 0
  fi

  local lock_dir="$VAULT_PATH/.lesson-promoter.lock"
  if ! _lp_acquire_lock "$lock_dir" 30; then
    echo "❌ promoter_apply_pending: could not acquire lock at $lock_dir" >&2
    return 1
  fi

  mkdir -p "$(dirname "$UNIVERSAL_TARGET")" "$(dirname "$ANTIPATTERN_TARGET")"
  _lp_init_target_if_missing "$UNIVERSAL_TARGET"   "Universal Patterns — Cross-Customer Lessons"
  _lp_init_target_if_missing "$ANTIPATTERN_TARGET" "Anti-Patterns — Auto-Detected Cross-Customer"

  local applied_universal=0 applied_anti=0 audited=0 committed=0
  local skipped_idem=0 skipped_conflict=0

  local cluster_id verdict customer_count lesson_count route title_seed
  while IFS=$'\t' read -r cluster_id verdict customer_count lesson_count route title_seed; do
    [[ -z "$cluster_id" ]] && continue

    case "$verdict" in
      PROMOTE)
        local target=""
        case "$route" in
          universal-patterns) target="$UNIVERSAL_TARGET" ;;
          anti-patterns)      target="$ANTIPATTERN_TARGET" ;;
          *)                  echo "⚠️  PROMOTE row with route=$route — skipping" >&2; continue ;;
        esac

        local slug marker
        slug=$(_lp_slug "$title_seed")
        marker="<!-- AOS Phase 6 — auto-promoted: ${slug}-cluster-${cluster_id} -->"

        if grep -F -q "$marker" "$target" 2>/dev/null; then
          skipped_idem=$((skipped_idem+1))
          continue
        fi

        local block_tmp
        block_tmp=$(mktemp -t ark-promoter-block-XXXXXXXX)
        {
          echo ""
          echo "$marker"
          echo "## ${title_seed}"
          echo ""
          echo "**Customers:** $(_lp_customers_for "$cluster_id")"
          echo "**Combined occurrences:** ${lesson_count}"
          echo "**Cluster ID:** ${cluster_id}"
          echo "**Promoted:** $(date -u +%Y-%m-%dT%H:%M:%SZ)"
          echo ""
          _lp_seed_body_for "$cluster_id"
          echo ""
          echo "**Source lessons:**"
          _lp_citations_for "$cluster_id"
          echo ""
          echo "---"
        } > "$block_tmp"

        local target_tmp="${target}.tmp.$$"
        if cat "$target" "$block_tmp" > "$target_tmp" 2>/dev/null; then
          mv "$target_tmp" "$target"
        else
          rm -f "$target_tmp" "$block_tmp"
          echo "⚠️  Failed to append to $target — skipping" >&2
          continue
        fi
        rm -f "$block_tmp"

        if [[ "$route" == "universal-patterns" ]]; then
          applied_universal=$((applied_universal+1))
        elif [[ "$route" == "anti-patterns" ]]; then
          applied_anti=$((applied_anti+1))
        fi

        # Audit (single-writer rule)
        local ctx
        ctx=$(printf '{"cluster_id":%s,"title_seed":"%s","lesson_count":%s,"route":"%s"}' \
          "$cluster_id" "$(printf '%s' "$title_seed" | sed 's/\\/\\\\/g; s/"/\\"/g')" \
          "$lesson_count" "$route")
        if type _policy_log >/dev/null 2>&1; then
          _policy_log "lesson_promote" "PROMOTED" \
            "customers_${customer_count}_lessons_${lesson_count}_route_${route}" \
            "$ctx" "" >/dev/null
          audited=$((audited+1))
        fi

        # Vault git commit
        if git -C "$VAULT_PATH" rev-parse --git-dir >/dev/null 2>&1; then
          local rel="${target#$VAULT_PATH/}"
          git -C "$VAULT_PATH" add "$rel" >/dev/null 2>&1 || true
          if ! git -C "$VAULT_PATH" diff --cached --quiet -- "$rel" 2>/dev/null; then
            git -C "$VAULT_PATH" commit -m \
              "AOS Phase 6: promote cluster ${cluster_id} (${route}) — ${title_seed}" \
              --quiet >/dev/null 2>&1 || true
            committed=$((committed+1))
          fi
        fi
        ;;
      DEPRECATED)
        local ctx
        ctx=$(printf '{"cluster_id":%s,"title_seed":"%s","lesson_count":%s,"route":"none"}' \
          "$cluster_id" "$(printf '%s' "$title_seed" | sed 's/\\/\\\\/g; s/"/\\"/g')" \
          "$lesson_count")
        if type _policy_log >/dev/null 2>&1; then
          _policy_log "lesson_promote" "DEPRECATED" \
            "conflict_customers_${customer_count}_lessons_${lesson_count}" \
            "$ctx" "" >/dev/null
          audited=$((audited+1))
        fi
        skipped_conflict=$((skipped_conflict+1))
        ;;
      MEDIOCRE_KEPT_PER_CUSTOMER)
        if [[ "${LESSON_AUDIT_MEDIOCRE:-0}" == "1" ]] && type _policy_log >/dev/null 2>&1; then
          local ctx
          ctx=$(printf '{"cluster_id":%s,"title_seed":"%s","lesson_count":%s,"route":"none"}' \
            "$cluster_id" "$(printf '%s' "$title_seed" | sed 's/\\/\\\\/g; s/"/\\"/g')" \
            "$lesson_count")
          _policy_log "lesson_promote" "MEDIOCRE_KEPT_PER_CUSTOMER" \
            "below_threshold_customers_${customer_count}" \
            "$ctx" "" >/dev/null
          audited=$((audited+1))
        fi
        ;;
    esac
  done < "$verdicts"

  _lp_release_lock "$lock_dir"

  echo "applied: $((applied_universal+applied_anti)) (universal: $applied_universal, anti: $applied_anti, audited: $audited, committed: $committed, skipped_idempotent: $skipped_idem, skipped_conflict: $skipped_conflict)"
  return 0
}
# === END SECTION: apply-pending ===

# === promoter_run [--full | --since DATE] [--apply] [--dry-run] ===
promoter_run() {
  local mode="full"
  local since=""
  local apply=0
  local dry_run=0

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --full)    mode="full"; shift ;;
      --since)   mode="since"; since="${2:-}"; shift 2 ;;
      --apply)   apply=1; shift ;;
      --dry-run) dry_run=1; shift ;;
      *)         shift ;;
    esac
  done

  if [[ "$mode" == "since" ]] && [[ -n "$since" ]]; then
    local since_epoch
    since_epoch=$(date -u -j -f "%Y-%m-%d" "$since" +%s 2>/dev/null \
      || date -u -d "$since" +%s 2>/dev/null \
      || echo 0)
    export LP_SINCE_EPOCH="$since_epoch"
  else
    export LP_SINCE_EPOCH=0
  fi

  local scan_tsv cluster_tsv verdicts_tsv
  scan_tsv=$(promoter_scan_lessons "$ARK_PORTFOLIO_ROOT")
  local scan_tmpdir="${LP_LAST_SCAN_TMPDIR:-}"
  trap '[[ -n "${scan_tmpdir:-}" ]] && rm -rf "$scan_tmpdir"' EXIT

  if [[ -z "$scan_tsv" ]]; then
    echo "clusters: 0 (promote: 0, deprecate: 0, mediocre: 0)"
    return 0
  fi

  cluster_tsv=$(printf '%s\n' "$scan_tsv" | promoter_cluster_similar)
  verdicts_tsv=$(printf '%s\n' "$cluster_tsv" | promoter_classify_cluster)

  if [[ "$dry_run" -eq 1 ]]; then
    printf '%s\n' "$verdicts_tsv"
    return 0
  fi

  local p d m
  p=$(printf '%s\n' "$verdicts_tsv" | awk -F'\t' '$2=="PROMOTE"' | wc -l | tr -d ' ')
  d=$(printf '%s\n' "$verdicts_tsv" | awk -F'\t' '$2=="DEPRECATED"' | wc -l | tr -d ' ')
  m=$(printf '%s\n' "$verdicts_tsv" | awk -F'\t' '$2=="MEDIOCRE_KEPT_PER_CUSTOMER"' | wc -l | tr -d ' ')
  echo "clusters: $((p+d+m)) (promote: $p, deprecate: $d, mediocre: $m)"

  if [[ "$apply" -eq 1 ]]; then
    local verdicts_file cluster_file
    verdicts_file=$(mktemp -t ark-promoter-verdicts-XXXXXXXX)
    cluster_file=$(mktemp -t ark-promoter-clusters-XXXXXXXX)
    printf '%s\n' "$verdicts_tsv" > "$verdicts_file"
    printf '%s\n' "$cluster_tsv"  > "$cluster_file"
    LP_CLUSTER_TSV="$cluster_file" promoter_apply_pending "$verdicts_file"
    rm -f "$verdicts_file" "$cluster_file"
  fi
}

# === CLI / Self-test ===
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  case "${1:-}" in
    scan)        shift; promoter_scan_lessons "${1:-$ARK_PORTFOLIO_ROOT}"; exit 0 ;;
    cluster)     promoter_cluster_similar; exit 0 ;;
    classify)    promoter_classify_cluster; exit 0 ;;
    run|--full)  promoter_run --full; exit 0 ;;
    --since)     shift; promoter_run --since "${1:-}"; exit 0 ;;
    --apply)     promoter_run --apply; exit 0 ;;
    --dry-run)   promoter_run --dry-run; exit 0 ;;
    test)        : ;;  # fall through to self-test
    "")          echo "Usage: $0 [test|scan|cluster|classify|run|--full|--since DATE|--apply|--dry-run]" >&2; exit 1 ;;
    *)           echo "Usage: $0 [test|scan|cluster|classify|run|--full|--since DATE|--apply|--dry-run]" >&2; exit 1 ;;
  esac

  # ---- Self-test ----
  echo "lesson-promoter.sh self-test"
  echo ""

  pass=0
  fail=0
  assert_eq() {
    local expected="$1" actual="$2" label="$3"
    if [[ "$expected" == "$actual" ]]; then
      echo "  PASS $label"
      pass=$((pass + 1))
    else
      echo "  FAIL $label  (expected: '$expected', got: '$actual')"
      fail=$((fail + 1))
    fi
  }
  assert_ge() {
    local lo="$1" actual="$2" label="$3"
    if [[ "$actual" =~ ^[0-9]+$ ]] && [[ "$actual" -ge "$lo" ]]; then
      echo "  PASS $label  (got $actual, expected >=$lo)"
      pass=$((pass + 1))
    else
      echo "  FAIL $label  (got '$actual', expected >=$lo)"
      fail=$((fail + 1))
    fi
  }

  # --- Real-vault md5 capture (BEFORE any test work) ---
  REAL_VAULT_FILE="$HOME/vaults/ark/lessons/universal-patterns.md"
  REAL_VAULT_ANTI="$HOME/vaults/ark/bootstrap/anti-patterns.md"
  REAL_VAULT_DB="$HOME/vaults/ark/observability/policy.db"
  if [[ -f "$REAL_VAULT_FILE" ]]; then
    REAL_MD5_BEFORE=$(md5 -q "$REAL_VAULT_FILE" 2>/dev/null \
      || md5sum "$REAL_VAULT_FILE" 2>/dev/null | awk '{print $1}')
  else
    REAL_MD5_BEFORE=""
  fi
  if [[ -f "$REAL_VAULT_ANTI" ]]; then
    REAL_MD5_ANTI_BEFORE=$(md5 -q "$REAL_VAULT_ANTI" 2>/dev/null \
      || md5sum "$REAL_VAULT_ANTI" 2>/dev/null | awk '{print $1}')
  else
    REAL_MD5_ANTI_BEFORE=""
  fi
  if [[ -f "$REAL_VAULT_DB" ]]; then
    REAL_MD5_DB_BEFORE=$(md5 -q "$REAL_VAULT_DB" 2>/dev/null \
      || md5sum "$REAL_VAULT_DB" 2>/dev/null | awk '{print $1}')
  else
    REAL_MD5_DB_BEFORE=""
  fi

  # --- Build isolated portfolio + tmp vault ---
  TEST_PORTFOLIO=$(mktemp -d -t ark-promoter-test-XXXXXXXX)
  TEST_VAULT=$(mktemp -d -t ark-promoter-vault-XXXXXXXX)
  mkdir -p "$TEST_VAULT/lessons" "$TEST_VAULT/bootstrap"
  : > "$TEST_VAULT/lessons/universal-patterns.md"
  : > "$TEST_VAULT/bootstrap/anti-patterns.md"
  CANARY_BEFORE=$(md5 -q "$TEST_VAULT/lessons/universal-patterns.md" 2>/dev/null \
    || md5sum "$TEST_VAULT/lessons/universal-patterns.md" 2>/dev/null | awk '{print $1}')

  export ARK_PORTFOLIO_ROOT="$TEST_PORTFOLIO"
  export VAULT_PATH="$TEST_VAULT"
  export ARK_HOME="$TEST_VAULT"
  export UNIVERSAL_TARGET="$TEST_VAULT/lessons/universal-patterns.md"
  export ANTIPATTERN_TARGET="$TEST_VAULT/bootstrap/anti-patterns.md"

  trap 'rm -rf "$TEST_PORTFOLIO" "$TEST_VAULT" "${LP_LAST_SCAN_TMPDIR:-/nonexistent-xyz}"' EXIT

  mkdir -p "$TEST_PORTFOLIO/cust-a/tasks" \
           "$TEST_PORTFOLIO/cust-b/tasks" \
           "$TEST_PORTFOLIO/cust-c/tasks"

  # cust-a: 3 lessons. Two RBAC variants (to satisfy ≥3 occurrence threshold
  # together with cust-b), one wrangler.
  cat > "$TEST_PORTFOLIO/cust-a/tasks/lessons.md" <<'EOF'
# Lessons Learned

## Lesson: Centralise RBAC role arrays in single source of truth
**Trigger:** Inline role arrays drifted between routes and middleware
**Mistake:** Hardcoded role list in three different files
**Rule:** Every RBAC role array must live in one centralised module. Routes and components import the array. Lint forbids inline role arrays. Centralised role array is the single source of truth.
**Date:** 2026-04-01

## Lesson: RBAC role arrays must be centralised in single source module
**Trigger:** Role array drift caught in code review
**Mistake:** Inline role arrays scattered across components and routes
**Rule:** Centralise every RBAC role array in one single source of truth module. Routes and components must import the centralised role array. Lint forbids inline role arrays anywhere in source.
**Date:** 2026-04-03

## Lesson: Wrangler binding deploy requires explicit project name
**Trigger:** Wrong D1 binding deployed
**Mistake:** Assumed default project from wrangler.toml
**Rule:** Always pass --project-name explicitly when deploying wrangler pages with multiple environments.
**Date:** 2026-04-02
EOF

  # cust-b: 1 lesson highly similar to cust-a's first (RBAC centralisation).
  # NOTE: title + rule body must share most vocabulary to clear the 60% Jaccard
  # threshold (06-01 confirmed real-lesson scores are typically <10%; fixture
  # is intentionally engineered to exceed the threshold).
  cat > "$TEST_PORTFOLIO/cust-b/tasks/lessons.md" <<'EOF'
# Lessons Learned

## Lesson: Centralise RBAC role arrays in single source of truth
**Trigger:** Inline role arrays drifted between routes and components
**Mistake:** Hardcoded role list in different files instead of centralised module
**Rule:** Every RBAC role array must live in one centralised module. Routes and components import the array. Lint forbids inline role arrays. Centralised role array is single source of truth.
**Date:** 2026-04-05
EOF

  # cust-c: 1 anti-pattern lesson + 1 unrelated migration lesson
  cat > "$TEST_PORTFOLIO/cust-c/tasks/lessons.md" <<'EOF'
# Lessons Learned

## Lesson: Anti-pattern: don't hardcode secrets in source code
**Trigger:** API key was committed to git history
**Mistake:** Hardcoded the key inline instead of using env var
**Rule:** Anti-pattern: never hardcode secrets. Always use environment variables or a secret manager. Don't commit secrets to source.
**Date:** 2026-04-10

## Lesson: Always run migrations after push
**Trigger:** Schema drift in prod
**Mistake:** Forgot to run migrations after deploying code
**Rule:** Always run wrangler d1 migrations apply after pushing schema changes. Verify production schema matches repository schema.
**Date:** 2026-04-12
EOF

  # --- Assertion 1: scan returns >= 5 rows ---
  scan_out=$(promoter_scan_lessons "$TEST_PORTFOLIO")
  scan_count=$(printf '%s\n' "$scan_out" | grep -c . || true)
  scan_count=$(echo "$scan_count" | tr -d ' \n')
  assert_ge 5 "$scan_count" "scan emits >=5 lesson rows across 3 customers"

  # --- Assertion 2: each row has 4 tab-separated fields ---
  bad_rows=$(printf '%s\n' "$scan_out" | awk -F'\t' 'NF != 4' | grep -c . || true)
  bad_rows=$(echo "$bad_rows" | tr -d ' \n')
  assert_eq "0" "$bad_rows" "every scan row has exactly 4 tab-separated fields"

  # --- Assertion 3: anti-pattern row has severity=anti ---
  anti_rows=$(printf '%s\n' "$scan_out" | awk -F'\t' '$4=="anti"' | grep -c . || true)
  anti_rows=$(echo "$anti_rows" | tr -d ' \n')
  assert_ge 1 "$anti_rows" "anti-pattern lesson has severity=anti"

  # --- Assertion 4: clustering produces a cluster spanning cust-a + cust-b ---
  cluster_out=$(printf '%s\n' "$scan_out" | promoter_cluster_similar)
  # Find a cluster_id that includes BOTH cust-a and cust-b
  shared_cluster=$(printf '%s\n' "$cluster_out" \
    | awk -F'\t' '{ key=$1; cust[key]=cust[key]","$2 }
                  END { for (k in cust) print k"\t"cust[k] }' \
    | awk -F'\t' '$2 ~ /cust-a/ && $2 ~ /cust-b/ { print $1 }' | head -1)
  if [[ -n "$shared_cluster" ]]; then
    echo "  PASS cust-a + cust-b RBAC lessons cluster (cluster_id=$shared_cluster)"
    pass=$((pass + 1))
  else
    echo "  FAIL cust-a + cust-b RBAC lessons did NOT cluster (similarity < 60?)"
    echo "----- scan_out -----"; printf '%s\n' "$scan_out"
    echo "----- cluster_out -----"; printf '%s\n' "$cluster_out"
    fail=$((fail + 1))
  fi

  # --- Assertion 5: that cluster classifies as PROMOTE w/ universal-patterns route ---
  verdict_out=$(printf '%s\n' "$cluster_out" | promoter_classify_cluster)
  if [[ -n "$shared_cluster" ]]; then
    shared_verdict=$(printf '%s\n' "$verdict_out" | awk -F'\t' -v c="$shared_cluster" '$1==c { print $2 }')
    shared_route=$(printf '%s\n' "$verdict_out" | awk -F'\t' -v c="$shared_cluster" '$1==c { print $5 }')
    shared_custcount=$(printf '%s\n' "$verdict_out" | awk -F'\t' -v c="$shared_cluster" '$1==c { print $3 }')
    assert_eq "PROMOTE" "$shared_verdict" "RBAC cluster verdict=PROMOTE"
    assert_eq "universal-patterns" "$shared_route" "RBAC cluster route=universal-patterns"
    assert_eq "2" "$shared_custcount" "RBAC cluster customer_count=2"
  else
    fail=$((fail + 3))
    echo "  FAIL skipped 3 verdict assertions (no shared cluster)"
  fi

  # --- Assertion 6: lone anti-pattern with 1 customer → MEDIOCRE_KEPT_PER_CUSTOMER ---
  # Find cluster containing the anti-pattern (severity=anti) which has only cust-c
  anti_cluster=$(printf '%s\n' "$cluster_out" \
    | awk -F'\t' '$5=="anti" { print $1 }' | head -1)
  if [[ -n "$anti_cluster" ]]; then
    anti_verdict=$(printf '%s\n' "$verdict_out" | awk -F'\t' -v c="$anti_cluster" '$1==c { print $2 }')
    assert_eq "MEDIOCRE_KEPT_PER_CUSTOMER" "$anti_verdict" "single-customer anti-pattern → MEDIOCRE (count threshold honored)"
  else
    fail=$((fail + 1))
    echo "  FAIL no anti cluster found"
  fi

  # --- Assertion 7: add anti-pattern lessons to cust-a AND cust-b → re-run, verdict=PROMOTE w/ route=anti-patterns ---
  cat >> "$TEST_PORTFOLIO/cust-a/tasks/lessons.md" <<'EOF'

## Lesson: Anti-pattern: don't hardcode secrets in source code
**Trigger:** API key committed
**Mistake:** Hardcoded secret value inline
**Rule:** Anti-pattern: never hardcode secrets. Always use environment variables or a secret manager. Don't commit secrets to source.
**Date:** 2026-04-15
EOF
  cat >> "$TEST_PORTFOLIO/cust-b/tasks/lessons.md" <<'EOF'

## Lesson: Anti-pattern: don't hardcode secrets in source code
**Trigger:** Token leaked in repo
**Mistake:** Hardcoded the secret token inline
**Rule:** Anti-pattern: never hardcode secrets. Always use environment variables or a secret manager. Don't commit secrets to source.
**Date:** 2026-04-16
EOF
  # Re-scan + cluster + classify
  scan_out2=$(promoter_scan_lessons "$TEST_PORTFOLIO")
  cluster_out2=$(printf '%s\n' "$scan_out2" | promoter_cluster_similar)
  verdict_out2=$(printf '%s\n' "$cluster_out2" | promoter_classify_cluster)
  # Find cluster that contains rows with severity=anti AND >=2 distinct customers
  anti_promote=$(printf '%s\n' "$cluster_out2" \
    | awk -F'\t' '$5=="anti" { print $1 }' | sort -u \
    | while IFS= read -r cid; do
        [[ -z "$cid" ]] && continue
        cc=$(awk -F'\t' -v c="$cid" '$1==c { print $2 }' <<< "$cluster_out2" | sort -u | wc -l | tr -d ' ')
        if [[ "$cc" -ge 2 ]]; then echo "$cid"; break; fi
      done)
  if [[ -n "$anti_promote" ]]; then
    anti_v=$(printf '%s\n' "$verdict_out2" | awk -F'\t' -v c="$anti_promote" '$1==c { print $2 }')
    anti_r=$(printf '%s\n' "$verdict_out2" | awk -F'\t' -v c="$anti_promote" '$1==c { print $5 }')
    assert_eq "PROMOTE" "$anti_v" "multi-customer anti-pattern verdict=PROMOTE"
    assert_eq "anti-patterns" "$anti_r" "multi-customer anti-pattern route=anti-patterns"
  else
    fail=$((fail + 2))
    echo "  FAIL no multi-customer anti-pattern cluster found after seeding"
  fi

  # --- Assertion 8: promoter_run --dry-run prints verdicts TSV ---
  dry_out=$(promoter_run --dry-run 2>/dev/null)
  dry_lines=$(printf '%s\n' "$dry_out" | grep -c . || true)
  dry_lines=$(echo "$dry_lines" | tr -d ' \n')
  assert_ge 1 "$dry_lines" "promoter_run --dry-run emits verdicts TSV"

  # --- Assertion 9: promoter_run --full does NOT mutate canary universal-patterns.md ---
  promoter_run --full >/dev/null 2>&1
  CANARY_AFTER=$(md5 -q "$TEST_VAULT/lessons/universal-patterns.md" 2>/dev/null \
    || md5sum "$TEST_VAULT/lessons/universal-patterns.md" 2>/dev/null | awk '{print $1}')
  assert_eq "$CANARY_BEFORE" "$CANARY_AFTER" "promoter_run --full does NOT mutate canary universal-patterns.md (no apply)"

  # --- Assertion 10: real-vault md5 unchanged before/after self-test ---
  if [[ -n "$REAL_MD5_BEFORE" ]]; then
    REAL_MD5_AFTER=$(md5 -q "$REAL_VAULT_FILE" 2>/dev/null \
      || md5sum "$REAL_VAULT_FILE" 2>/dev/null | awk '{print $1}')
    assert_eq "$REAL_MD5_BEFORE" "$REAL_MD5_AFTER" "real-vault universal-patterns.md md5 unchanged"
  else
    echo "  PASS real-vault file did not exist before test (no mutation possible)"
    pass=$((pass + 1))
  fi

  # --- Assertion 11: section sentinel for 06-03 present ---
  sentinel_open=$(grep -c '^# === SECTION: apply-pending (Plan 06-03) ===' "$0" || true)
  sentinel_open=$(echo "$sentinel_open" | tr -d ' \n')
  assert_eq "1" "$sentinel_open" "06-03 sentinel section open marker present"
  sentinel_close=$(grep -c '^# === END SECTION: apply-pending ===' "$0" || true)
  sentinel_close=$(echo "$sentinel_close" | tr -d ' \n')
  assert_eq "1" "$sentinel_close" "06-03 sentinel section close marker present"

  # --- Assertion 12: bash-3 compat scan in lib region (above guard) ---
  guard_line=$(awk '/^if[[:space:]]+\[\[[[:space:]]+"\$\{BASH_SOURCE\[0\]\}"[[:space:]]+==[[:space:]]+"\$\{0\}"[[:space:]]+\]\];[[:space:]]+then/ { print NR; exit }' "$0")
  if [[ -z "$guard_line" ]]; then
    guard_line=$(grep -n 'BASH_SOURCE\[0\]' "$0" | head -1 | cut -d: -f1)
  fi
  if [[ -n "$guard_line" ]]; then
    bad=$(head -n "$guard_line" "$0" \
      | grep -v '^[[:space:]]*#' \
      | grep -cE '(^|[[:space:]])(declare -A|mapfile|readarray)([[:space:]]|$)' || true)
    bad=$(echo "$bad" | tr -d ' \n')
    assert_eq "0" "$bad" "bash-3 compat: 0 declare-A/mapfile/readarray in lib region"
  else
    echo "  FAIL bash-3 compat scan: could not locate guard line"
    fail=$((fail + 1))
  fi

  # --- Assertion 13: no `read -p` in lib region ---
  if [[ -n "$guard_line" ]]; then
    rp_hits=$(head -n "$guard_line" "$0" \
      | grep -v '^[[:space:]]*#' \
      | grep -cE '(^|[^A-Za-z_])read[[:space:]]+-p[[:space:]]' || true)
    rp_hits=$(echo "$rp_hits" | tr -d ' \n')
    assert_eq "0" "$rp_hits" "no 'read -p' in lib region"
  else
    fail=$((fail + 1))
  fi

  # --- Assertion 14: $VAULT_PATH was redirected to tmp during test ---
  case "$VAULT_PATH" in
    /tmp/*|/var/folders/*) vp_isolated=1 ;;
    *)                     vp_isolated=0 ;;
  esac
  assert_eq "1" "$vp_isolated" "VAULT_PATH redirected to tmp dir during self-test (real-vault isolation)"

  # ============================================================================
  # Plan 06-03: promoter_apply_pending — atomic write + git + audit + idempotency
  # ============================================================================
  echo ""
  echo "Plan 06-03: promoter_apply_pending (atomic write + git + audit + idempotency)"
  echo ""

  # --- Isolated apply test environment (separate from outer canary so we keep
  #     assertion 9's canary contract intact). Init tmp vault as a git repo +
  #     attach a tmp policy.db so we can audit-count without touching real DB. ---
  APPLY_VAULT=$(mktemp -d -t ark-promoter-apply-XXXXXXXX)
  APPLY_DB="${TMPDIR:-/tmp}/ark-promoter-apply-$$.db"
  mkdir -p "$APPLY_VAULT/lessons" "$APPLY_VAULT/bootstrap" "$APPLY_VAULT/observability"

  export VAULT_PATH="$APPLY_VAULT"
  export ARK_HOME="$APPLY_VAULT"
  export UNIVERSAL_TARGET="$APPLY_VAULT/lessons/universal-patterns.md"
  export ANTIPATTERN_TARGET="$APPLY_VAULT/bootstrap/anti-patterns.md"
  export ARK_POLICY_DB="$APPLY_DB"
  rm -f "$APPLY_DB" "$APPLY_DB-shm" "$APPLY_DB-wal"
  if type db_init >/dev/null 2>&1; then
    db_init >/dev/null 2>&1 || true
  fi

  # Insert parent decision row so any FK on correlation_id has something to point at.
  if type sqlite3 >/dev/null 2>&1; then
    sqlite3 "$APPLY_DB" "INSERT OR IGNORE INTO decisions (decision_id, ts, class, decision, reason, context, outcome) VALUES ('lp_seed', '2026-04-26T00:00:00Z', 'lesson_promote', 'PROMOTED', 'seed', '{}', 'success');" 2>/dev/null || true
  fi

  ( cd "$APPLY_VAULT" \
    && git init --quiet \
    && git config user.email "test@example.invalid" \
    && git config user.name "Apply Test" \
    && git config commit.gpgsign false ) >/dev/null 2>&1

  # Use the same TEST_PORTFOLIO fixture (3 customers w/ RBAC + anti-pattern).
  export ARK_PORTFOLIO_ROOT="$TEST_PORTFOLIO"

  # === Test 1: full pipeline run --apply against isolated vault ===
  apply1_out=$(promoter_run --apply 2>&1)

  # universal-patterns.md was created
  [[ -s "$UNIVERSAL_TARGET" ]] && up1=1 || up1=0
  assert_eq "1" "$up1" "06-03: universal-patterns.md created with content after --apply"

  # anti-patterns.md was created (init header at minimum)
  [[ -s "$ANTIPATTERN_TARGET" ]] && ap1=1 || ap1=0
  assert_eq "1" "$ap1" "06-03: anti-patterns.md created with content after --apply"

  # universal-patterns.md contains the canonical marker for at least one cluster
  univ_markers=$(grep -c '<!-- AOS Phase 6 — auto-promoted: .*-cluster-' "$UNIVERSAL_TARGET" 2>/dev/null || echo 0)
  univ_markers=$(echo "$univ_markers" | tr -d ' \n')
  assert_ge 1 "$univ_markers" "06-03: universal-patterns.md has >=1 cluster canonical marker"

  # anti-patterns.md contains the anti-pattern marker (cust-a + cust-b have anti-pattern lessons)
  anti_markers=$(grep -c '<!-- AOS Phase 6 — auto-promoted: .*-cluster-' "$ANTIPATTERN_TARGET" 2>/dev/null || echo 0)
  anti_markers=$(echo "$anti_markers" | tr -d ' \n')
  assert_ge 1 "$anti_markers" "06-03: anti-patterns.md has >=1 cluster canonical marker"

  # Audit DB has lesson_promote PROMOTED rows
  if type sqlite3 >/dev/null 2>&1; then
    promoted_rows=$(sqlite3 "$APPLY_DB" "SELECT count(*) FROM decisions WHERE class='lesson_promote' AND decision='PROMOTED';" 2>/dev/null || echo 0)
    assert_ge 2 "$promoted_rows" "06-03: audit DB has >=2 lesson_promote PROMOTED rows"
  else
    echo "  SKIP audit DB checks (sqlite3 unavailable)"
  fi

  # Git log has Phase 6 commits
  commit_count1=$(git -C "$APPLY_VAULT" log --oneline --all 2>/dev/null | grep -c "AOS Phase 6: promote cluster" || true)
  commit_count1=$(echo "$commit_count1" | tr -d ' \n')
  assert_ge 2 "$commit_count1" "06-03: tmp vault has >=2 'AOS Phase 6: promote cluster' git commits"

  # Lock dir absent after run
  [[ -d "$APPLY_VAULT/.lesson-promoter.lock" ]] && lk1=1 || lk1=0
  assert_eq "0" "$lk1" "06-03: lock dir absent after --apply"

  # No leftover .tmp.* files in vault target dirs
  leftover_tmp=$(find "$APPLY_VAULT/lessons" "$APPLY_VAULT/bootstrap" -name '*.tmp.*' 2>/dev/null | wc -l | tr -d ' ')
  assert_eq "0" "$leftover_tmp" "06-03: no .tmp.* leftovers in vault target dirs"

  # === Test 2: idempotency — re-run produces no new commits, no new audit rows, no new appends ===
  univ_lines_before=$(wc -l < "$UNIVERSAL_TARGET" | tr -d ' ')
  anti_lines_before=$(wc -l < "$ANTIPATTERN_TARGET" | tr -d ' ')
  if type sqlite3 >/dev/null 2>&1; then
    promoted_rows_before=$(sqlite3 "$APPLY_DB" "SELECT count(*) FROM decisions WHERE class='lesson_promote' AND decision='PROMOTED';" 2>/dev/null || echo 0)
  fi
  commit_count_before=$(git -C "$APPLY_VAULT" log --oneline --all 2>/dev/null | wc -l | tr -d ' ')

  promoter_run --apply >/dev/null 2>&1

  univ_lines_after=$(wc -l < "$UNIVERSAL_TARGET" | tr -d ' ')
  anti_lines_after=$(wc -l < "$ANTIPATTERN_TARGET" | tr -d ' ')
  commit_count_after=$(git -C "$APPLY_VAULT" log --oneline --all 2>/dev/null | wc -l | tr -d ' ')

  assert_eq "$univ_lines_before" "$univ_lines_after" "06-03 idempotency: universal-patterns.md line count unchanged on re-run"
  assert_eq "$anti_lines_before" "$anti_lines_after" "06-03 idempotency: anti-patterns.md line count unchanged on re-run"
  assert_eq "$commit_count_before" "$commit_count_after" "06-03 idempotency: git commit count unchanged on re-run"
  if type sqlite3 >/dev/null 2>&1; then
    promoted_rows_after=$(sqlite3 "$APPLY_DB" "SELECT count(*) FROM decisions WHERE class='lesson_promote' AND decision='PROMOTED';" 2>/dev/null || echo 0)
    assert_eq "$promoted_rows_before" "$promoted_rows_after" "06-03 idempotency: audit DB PROMOTED row count unchanged on re-run"
  fi

  # === Test 3: DEPRECATED verdict — audit row, no file write ===
  # Manually craft a verdicts TSV with a DEPRECATED conflict cluster row.
  CONF_VERDICTS=$(mktemp -t ark-promoter-conf-verdicts-XXXXXXXX)
  CONF_CLUSTERS=$(mktemp -t ark-promoter-conf-clusters-XXXXXXXX)
  printf '999\tDEPRECATED\t2\t3\tnone\tConflict cluster do vs dont\n' > "$CONF_VERDICTS"
  : > "$CONF_CLUSTERS"  # empty — _lp_*_for helpers not invoked for DEPRECATED rows
  univ_lines_pre_dep=$(wc -l < "$UNIVERSAL_TARGET" | tr -d ' ')
  if type sqlite3 >/dev/null 2>&1; then
    dep_rows_before=$(sqlite3 "$APPLY_DB" "SELECT count(*) FROM decisions WHERE class='lesson_promote' AND decision='DEPRECATED';" 2>/dev/null || echo 0)
  fi
  LP_CLUSTER_TSV="$CONF_CLUSTERS" promoter_apply_pending "$CONF_VERDICTS" >/dev/null 2>&1
  univ_lines_post_dep=$(wc -l < "$UNIVERSAL_TARGET" | tr -d ' ')
  assert_eq "$univ_lines_pre_dep" "$univ_lines_post_dep" "06-03 DEPRECATED: universal-patterns.md line count unchanged"
  if type sqlite3 >/dev/null 2>&1; then
    dep_rows_after=$(sqlite3 "$APPLY_DB" "SELECT count(*) FROM decisions WHERE class='lesson_promote' AND decision='DEPRECATED';" 2>/dev/null || echo 0)
    new_dep=$(( dep_rows_after - dep_rows_before ))
    assert_eq "1" "$new_dep" "06-03 DEPRECATED: exactly 1 new lesson_promote DEPRECATED audit row"
  fi
  rm -f "$CONF_VERDICTS" "$CONF_CLUSTERS"

  # === Test 4: concurrent --apply runs serialise via mkdir-lock ===
  # Synthetic verdict for new cluster (slug different from prior runs).
  CC_VERDICTS=$(mktemp -t ark-promoter-cc-verdicts-XXXXXXXX)
  CC_CLUSTERS=$(mktemp -t ark-promoter-cc-clusters-XXXXXXXX)
  printf '888\tPROMOTE\t2\t3\tuniversal-patterns\tConcurrent run cluster fixture\n' > "$CC_VERDICTS"
  : > "$CC_CLUSTERS"
  cc_commits_before=$(git -C "$APPLY_VAULT" log --oneline --all 2>/dev/null | wc -l | tr -d ' ')
  ( LP_CLUSTER_TSV="$CC_CLUSTERS" promoter_apply_pending "$CC_VERDICTS" >/dev/null 2>&1 ) &
  cpid1=$!
  ( LP_CLUSTER_TSV="$CC_CLUSTERS" promoter_apply_pending "$CC_VERDICTS" >/dev/null 2>&1 ) &
  cpid2=$!
  wait "$cpid1" 2>/dev/null
  wait "$cpid2" 2>/dev/null
  cc_commits_after=$(git -C "$APPLY_VAULT" log --oneline --all 2>/dev/null | wc -l | tr -d ' ')
  cc_delta=$(( cc_commits_after - cc_commits_before ))
  # Exactly one of the two siblings should have appended; the other should
  # see the canonical marker and skip. So delta must be exactly 1.
  assert_eq "1" "$cc_delta" "06-03 concurrent: exactly 1 new commit (mkdir-lock + idempotency serialised)"
  [[ -d "$APPLY_VAULT/.lesson-promoter.lock" ]] && cclk=1 || cclk=0
  assert_eq "0" "$cclk" "06-03 concurrent: lock dir released after parallel runs"
  rm -f "$CC_VERDICTS" "$CC_CLUSTERS"

  # === Test 5: real-vault md5 invariant (universal-patterns + anti-patterns + policy.db) ===
  if [[ -n "$REAL_MD5_BEFORE" ]]; then
    REAL_MD5_AFTER_APPLY=$(md5 -q "$REAL_VAULT_FILE" 2>/dev/null \
      || md5sum "$REAL_VAULT_FILE" 2>/dev/null | awk '{print $1}')
    assert_eq "$REAL_MD5_BEFORE" "$REAL_MD5_AFTER_APPLY" "06-03 real-vault: universal-patterns.md md5 unchanged"
  else
    echo "  PASS 06-03 real-vault: universal-patterns.md absent before+after (no mutation)"
    pass=$((pass + 1))
  fi
  if [[ -n "$REAL_MD5_ANTI_BEFORE" ]]; then
    REAL_MD5_ANTI_AFTER=$(md5 -q "$REAL_VAULT_ANTI" 2>/dev/null \
      || md5sum "$REAL_VAULT_ANTI" 2>/dev/null | awk '{print $1}')
    assert_eq "$REAL_MD5_ANTI_BEFORE" "$REAL_MD5_ANTI_AFTER" "06-03 real-vault: anti-patterns.md md5 unchanged"
  else
    echo "  PASS 06-03 real-vault: anti-patterns.md absent before+after (no mutation)"
    pass=$((pass + 1))
  fi
  if [[ -n "$REAL_MD5_DB_BEFORE" ]]; then
    REAL_MD5_DB_AFTER=$(md5 -q "$REAL_VAULT_DB" 2>/dev/null \
      || md5sum "$REAL_VAULT_DB" 2>/dev/null | awk '{print $1}')
    assert_eq "$REAL_MD5_DB_BEFORE" "$REAL_MD5_DB_AFTER" "06-03 real-vault: policy.db md5 unchanged"
  else
    echo "  PASS 06-03 real-vault: policy.db absent before+after (no mutation)"
    pass=$((pass + 1))
  fi

  # === Cleanup apply-test isolation ===
  rm -rf "$APPLY_VAULT"
  rm -f "$APPLY_DB" "$APPLY_DB-shm" "$APPLY_DB-wal"

  echo ""
  if [[ "$fail" -eq 0 ]]; then
    echo "✅ ALL APPLY-PENDING TESTS PASSED"
  fi

  echo ""
  if [[ "$fail" -eq 0 ]]; then
    echo "ALL LESSON-PROMOTER TESTS PASSED ($pass/$pass)"
    echo ""
    echo "✅ ALL LESSON-PROMOTER TESTS PASSED"
    exit 0
  else
    echo "$fail/$((pass+fail)) tests failed"
    exit 1
  fi
fi
