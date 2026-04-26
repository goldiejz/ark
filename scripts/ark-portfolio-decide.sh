#!/usr/bin/env bash
# ark-portfolio-decide.sh — AOS Phase 5 Portfolio Priority Engine
#
# Sourceable Bash 3 library. Walks the portfolio root, scores each candidate
# project, and selects the highest-priority project for autonomous delivery.
#
# Public API:
#   portfolio_scan_candidates [root]    -> echoes one project path per line
#   portfolio_score_project <path>      -> 8-field TSV:
#       <path>\t<customer>\t<phase>\t<stuckness>\t<falling_health>\t
#       <budget_headroom>\t<ceo_priority>\t<total>
#   portfolio_pick_winner [root]        -> echoes winning project path (or empty)
#   portfolio_decide [root]             -> picks + audit-logs via _policy_log
#
# Priority formula (D-PRIORITY-FORMULA, locked in CONTEXT.md):
#   priority = stuckness * 3
#            + falling_health * 2
#            + (monthly_headroom > 20 ? 1 : 0)
#            + ceo_priority * 5
#
# Decision classes (D-DECISION-CLASSES):
#   SELECTED                — winner picked
#   DEFERRED_BUDGET         — customer over 80% monthly cap (Plan 05-02)
#   DEFERRED_HEALTHY        — no work needed (Plan 05-04)
#   NO_CANDIDATE_AVAILABLE  — empty portfolio
#
# Sourced-lib discipline (mirrors scripts/lib/policy-config.sh):
#   - NO top-level `set -euo pipefail` — would propagate to callers.
#   - All private helpers prefixed `_portfolio_`; public API is `portfolio_*`.
#   - Single audit writer: every audit-class emission routes via `_policy_log`.
#
# Bash 3 compat (macOS default):
#   - NO `declare -A` (associative arrays)
#   - NO `${var,,}` lowercasing (use `tr '[:upper:]' '[:lower:]'`)
#   - NO `mapfile` / `readarray`
#   - NO `read -p` in delivery-path code
#
# This is the FOUNDATION plan (05-01). Wave-2 plans (05-02/03/04) fill the
# three sentinel sections at the bottom of this file in parallel without
# git conflicts (disjoint regions).

VAULT_PATH="${ARK_HOME:-$HOME/vaults/ark}"
ARK_PORTFOLIO_ROOT="${ARK_PORTFOLIO_ROOT:-$HOME/code}"

# === Source ark-policy.sh (graceful degradation if missing) ===
# Hide $1 from sourced script: ark-policy.sh has an inline `if [[ "${1:-}" == "test" ]]`
# self-test guard that would fire when we run `bash ark-portfolio-decide.sh test`.
_PORTFOLIO_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
if [[ -f "$_PORTFOLIO_LIB_DIR/ark-policy.sh" ]]; then
  _PORTFOLIO_SAVED_ARGS=("$@")
  set --
  # shellcheck disable=SC1091
  source "$_PORTFOLIO_LIB_DIR/ark-policy.sh"
  set -- "${_PORTFOLIO_SAVED_ARGS[@]}"
  unset _PORTFOLIO_SAVED_ARGS
else
  # Test-friendly stubs (echo invocation so tests can grep for them).
  _policy_log() { echo "stub:_policy_log class=$1 decision=$2 reason=$3 context=${4:-null}"; echo "stub-decision-id"; }
  policy_config_get() { echo "$2"; }
  policy_config_has() { return 1; }
fi

# === Private helpers ===

# _portfolio_mtime <path-to-file> — Unix epoch seconds; macOS first, GNU fallback.
_portfolio_mtime() {
  local f="$1"
  local mt
  [[ ! -e "$f" ]] && { echo 0; return 0; }
  mt=$(stat -f %m "$f" 2>/dev/null)
  if [[ -z "$mt" ]]; then
    mt=$(stat -c %Y "$f" 2>/dev/null)
  fi
  echo "${mt:-0}"
}

# _portfolio_read_yaml_key <file> <dotted.key> — minimal YAML scalar reader.
# Mirrors policy-config.sh::_pc_read_yaml_key (copy-not-source: that helper
# is private to its own module).
_portfolio_read_yaml_key() {
  local file="$1"
  local key="$2"
  [[ ! -f "$file" ]] && return 1
  awk -v k="$key" '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    {
      sub(/^[[:space:]]+/, "")
      idx = index($0, ":")
      if (idx == 0) next
      ykey = substr($0, 1, idx-1)
      val  = substr($0, idx+1)
      sub(/^[[:space:]]+/, "", val)
      sub(/[[:space:]]+$/, "", val)
      cidx = index(val, "#")
      if (cidx > 0) {
        val = substr(val, 1, cidx-1)
        sub(/[[:space:]]+$/, "", val)
      }
      if (substr(val, 1, 1) == "\"" && substr(val, length(val), 1) == "\"") {
        val = substr(val, 2, length(val)-2)
      }
      if (ykey == k) { print val; exit 0 }
    }
  ' "$file"
}

# _portfolio_read_customer <project_path> — echoes customer slug or "scratch".
_portfolio_read_customer() {
  local proj="$1"
  local pol="$proj/.planning/policy.yml"
  local v=""
  if [[ -f "$pol" ]]; then
    v=$(_portfolio_read_yaml_key "$pol" "bootstrap.customer")
  fi
  if [[ -z "$v" ]]; then
    echo "scratch"
  else
    echo "$v"
  fi
}

# _portfolio_stuckness <project_path> — echoes 0|1|2.
#   2 = STATE.md contains `status: blocked`
#   1 = STATE.md mtime older than 7 days
#   0 = otherwise
_portfolio_stuckness() {
  local proj="$1"
  local state="$proj/.planning/STATE.md"
  [[ ! -f "$state" ]] && { echo 0; return 0; }
  if grep -qE '^[[:space:]]*status:[[:space:]]*blocked' "$state" 2>/dev/null; then
    echo 2
    return 0
  fi
  local mt now age
  mt=$(_portfolio_mtime "$state")
  now=$(date +%s)
  age=$(( now - mt ))
  # 7 days = 604800 seconds
  if [[ "$age" -gt 604800 ]]; then
    echo 1
    return 0
  fi
  echo 0
}

# _portfolio_falling_health <project_path> — echoes 0|1.
# Conservative: any failure returns 0.
_portfolio_falling_health() {
  local proj="$1"
  local logdir="$proj/.planning/delivery-logs"
  [[ ! -d "$logdir" ]] && { echo 0; return 0; }
  # Newest log file
  local newest
  newest=$(ls -t "$logdir"/*.log 2>/dev/null | head -1)
  [[ -z "$newest" ]] && { echo 0; return 0; }
  # Extract last two numeric pass counts
  local nums
  nums=$(grep -oE '(pass count|tests passed)[^0-9]*[0-9]+' "$newest" 2>/dev/null \
         | grep -oE '[0-9]+' | tail -2)
  local cnt
  cnt=$(echo "$nums" | wc -l | tr -d ' ')
  if [[ "$cnt" -lt 2 ]]; then
    echo 0
    return 0
  fi
  local prev curr
  prev=$(echo "$nums" | head -1)
  curr=$(echo "$nums" | tail -1)
  if [[ -n "$prev" ]] && [[ -n "$curr" ]] && [[ "$curr" -lt "$prev" ]] 2>/dev/null; then
    echo 1
  else
    echo 0
  fi
}

# === Public: discovery ===
# portfolio_scan_candidates [root] — echoes one project path per line.
portfolio_scan_candidates() {
  local root="${1:-$ARK_PORTFOLIO_ROOT}"
  [[ ! -d "$root" ]] && return 0
  # Walk to depth 3, find .planning/STATE.md, dirname twice = project root.
  find "$root" -maxdepth 3 -type f -name STATE.md -path '*/.planning/STATE.md' 2>/dev/null \
    | while IFS= read -r state_md; do
        local planning_dir proj_dir
        planning_dir=$(dirname "$state_md")
        proj_dir=$(dirname "$planning_dir")
        echo "$proj_dir"
      done \
    | sort -u
}

# === Public: scoring ===
# portfolio_score_project <path> — echoes 8-field TSV row.
portfolio_score_project() {
  local proj="$1"
  [[ -z "$proj" ]] && return 1
  local state="$proj/.planning/STATE.md"

  local customer phase stuckness falling_health budget_headroom ceo_priority total
  customer=$(_portfolio_read_customer "$proj")
  phase=$(grep -oE 'Phase [0-9]+' "$state" 2>/dev/null | head -1)
  [[ -z "$phase" ]] && phase="?"
  stuckness=$(_portfolio_stuckness "$proj")
  falling_health=$(_portfolio_falling_health "$proj")

  # budget_headroom: filled by SECTION:budget-reader (Plan 05-02).
  # _portfolio_budget_headroom is always defined when this file is sourced;
  # the type-check survives only as defence against a half-source race.
  if type _portfolio_budget_headroom >/dev/null 2>&1; then
    budget_headroom=$(_portfolio_budget_headroom "$customer")
  else
    budget_headroom=$(( 100 ))  # safety fallback (function missing)
  fi

  # ceo_priority: filled by SECTION:ceo-directive (Plan 05-03).
  # _portfolio_ceo_priority is always defined when this file is sourced; the
  # type-check survives only as defence against a half-source race.
  if type _portfolio_ceo_priority >/dev/null 2>&1; then
    ceo_priority=$(_portfolio_ceo_priority "$proj")
  else
    ceo_priority=$(( 0 ))  # safety fallback (function missing)
  fi

  local headroom_bonus=0
  if [[ "$budget_headroom" -gt 20 ]] 2>/dev/null; then headroom_bonus=1; fi

  total=$(( stuckness * 3 + falling_health * 2 + headroom_bonus + ceo_priority * 5 ))

  # TSV with literal tabs (printf %s\t)
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$proj" "$customer" "$phase" "$stuckness" "$falling_health" \
    "$budget_headroom" "$ceo_priority" "$total"
}

# === Public: winner selection ===
# portfolio_pick_winner [root] — echoes winning project path or "" (exit 0 either way).
# Filter: skip rows where budget_headroom (field 6) <= 0 (Plan 05-02 hook).
# Sort: numerically descending by total (field 8); tie-break by mtime descending.
portfolio_pick_winner() {
  local root="${1:-$ARK_PORTFOLIO_ROOT}"
  local candidates
  candidates=$(portfolio_scan_candidates "$root")
  [[ -z "$candidates" ]] && { echo ""; return 0; }

  # Build temp file of: <total>\t<mtime>\t<project_path>
  local tmp
  tmp=$(mktemp -t ark-portfolio-pick.XXXXXX)
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    local row
    row=$(portfolio_score_project "$p" 2>/dev/null)
    [[ -z "$row" ]] && continue
    # Field 6 = budget_headroom; skip if <= 0
    local headroom total path mt
    headroom=$(echo "$row" | awk -F'\t' '{print $6}')
    if [[ "$headroom" -le 0 ]] 2>/dev/null; then continue; fi
    total=$(echo "$row" | awk -F'\t' '{print $8}')
    path=$(echo "$row" | awk -F'\t' '{print $1}')
    mt=$(_portfolio_mtime "$path/.planning/STATE.md")
    printf '%s\t%s\t%s\n' "$total" "$mt" "$path" >> "$tmp"
  done <<EOF_CAND
$candidates
EOF_CAND

  local winner=""
  if [[ -s "$tmp" ]]; then
    winner=$(sort -t $'\t' -k1,1nr -k2,2nr "$tmp" | head -1 | awk -F'\t' '{print $3}')
  fi
  rm -f "$tmp"
  echo "$winner"
}

# === Public: full decide flow ===
# portfolio_decide [root] — picks winner, audit-logs, echoes winner path.
# Plan 05-04 expands this with DEFERRED_BUDGET / DEFERRED_HEALTHY classes
# and 24h cool-down inside SECTION:audit-and-cooldown.
portfolio_decide() {
  local root="${1:-$ARK_PORTFOLIO_ROOT}"
  local winner
  winner=$(portfolio_pick_winner "$root")

  if [[ -z "$winner" ]]; then
    _policy_log "portfolio" "NO_CANDIDATE_AVAILABLE" "no_projects_under_${root}" "null" >/dev/null
    echo ""
    return 0
  fi

  # Serialize the winner's TSV breakdown as JSON context.
  local row customer phase stuckness fh headroom ceo total
  row=$(portfolio_score_project "$winner")
  customer=$(echo "$row" | awk -F'\t' '{print $2}')
  phase=$(echo "$row"    | awk -F'\t' '{print $3}')
  stuckness=$(echo "$row"| awk -F'\t' '{print $4}')
  fh=$(echo "$row"       | awk -F'\t' '{print $5}')
  headroom=$(echo "$row" | awk -F'\t' '{print $6}')
  ceo=$(echo "$row"      | awk -F'\t' '{print $7}')
  total=$(echo "$row"    | awk -F'\t' '{print $8}')

  local ctx
  ctx="{\"path\":\"$winner\",\"customer\":\"$customer\",\"phase\":\"$phase\",\"stuckness\":$stuckness,\"falling_health\":$fh,\"budget_headroom\":$headroom,\"ceo_priority\":$ceo,\"total\":$total}"

  _policy_log "portfolio" "SELECTED" "highest_priority_total=${total}" "$ctx" >/dev/null

  echo "$winner"
}

# === SECTION: budget-reader (Plan 05-02) ===
# Plan 05-02 owns this region. Defines _portfolio_budget_headroom() which
# overrides the stub in portfolio_score_project to read
# ~/vaults/ark/customers/<customer>/policy.yml::budget.monthly_used and
# budget.monthly_cap. Returns 0 (signals DEFERRED_BUDGET) when >= 80%.
#
# Signature note: 05-01 wired the caller as `_portfolio_budget_headroom "$customer"`
# (passes a customer slug, not a project path). We honor that contract here.
# Resolution path: ARK_CUSTOMER=<slug> + PROJECT_DIR="" → policy_config_get
# cascade hits the customer layer (Phase 4) directly.

# _portfolio_budget_headroom <customer>
# Returns 0..100 (percent headroom remaining): 100 = fresh, 0 = at/over 80% cap.
# Reads $ARK_HOME/customers/<customer>/policy.yml::budget.monthly_used and
# budget.monthly_cap via the cascading config layer (Phase 4 customer wiring).
# Default cap: 100000 tokens. Missing customer file → headroom 100 (fresh).
# scratch (no customer tag) → headroom 100 (no per-customer cap).
_portfolio_budget_headroom() {
  local customer="$1"
  # No customer / scratch → no per-customer cap; full headroom.
  if [[ -z "$customer" ]] || [[ "$customer" == "scratch" ]]; then
    echo 100
    return 0
  fi
  local used cap
  # PROJECT_DIR cleared so the project-level layer doesn't shadow the customer
  # layer for these specific keys. ARK_CUSTOMER pinned per-call.
  used=$(ARK_CUSTOMER="$customer" PROJECT_DIR="" \
         policy_config_get budget.monthly_used 0)
  cap=$(ARK_CUSTOMER="$customer" PROJECT_DIR="" \
         policy_config_get budget.monthly_cap 100000)
  # Defensive: non-numeric → assume fresh.
  case "$used" in ''|*[!0-9]*) used=0 ;; esac
  case "$cap"  in ''|*[!0-9]*) cap=100000 ;; esac
  if [[ "$cap" -le 0 ]]; then echo 100; return 0; fi
  local pct_used
  pct_used=$(( used * 100 / cap ))
  # ≥80% used → DEFERRED_BUDGET signal (headroom 0).
  if [[ "$pct_used" -ge 80 ]]; then echo 0; return 0; fi
  echo $(( 100 - pct_used ))
}

# _portfolio_global_fair_share <num_active_customers>
# Returns the remaining global token budget per customer (informational; used
# by Plan 05-04's portfolio_decide rationale logging — not by the score).
# Reads $ARK_HOME/policy.yml::budget.monthly_cap_total and monthly_used_total
# via vault-level cascade (no customer scope).
_portfolio_global_fair_share() {
  local n="${1:-1}"
  if [[ -z "$n" ]] || [[ "$n" -le 0 ]] 2>/dev/null; then n=1; fi
  local g_cap g_used
  g_cap=$(PROJECT_DIR="" policy_config_get budget.monthly_cap_total 1000000)
  g_used=$(PROJECT_DIR="" policy_config_get budget.monthly_used_total 0)
  case "$g_used" in ''|*[!0-9]*) g_used=0 ;; esac
  case "$g_cap"  in ''|*[!0-9]*) g_cap=1000000 ;; esac
  local rem=$(( g_cap - g_used ))
  [[ "$rem" -lt 0 ]] && rem=0
  echo $(( rem / n ))
}
# === END SECTION: budget-reader ===

# === SECTION: ceo-directive (Plan 05-03) ===
# Plan 05-03 owns this region. Defines _portfolio_ceo_priority() which
# parses ~/vaults/StrategixMSPDocs/programme.md `## Next Priority` heading.
# Returns 1 if project name matches; else 0.
#
# Source file resolution: $ARK_PROGRAMME_MD overrides
# $HOME/vaults/StrategixMSPDocs/programme.md. Missing file → 0 for all projects
# (graceful fallback to heuristic per CONTEXT.md Risks #2).
#
# Match rules (regex-tolerant):
#   - Heading: ^## <whitespace> Next <whitespace> Priority <whitespace> $
#   - Value: first non-blank, non-comment line after heading; stop at next "##".
#   - Strip leading bullet marker ("- " or "* "), leading whitespace, and
#     trailing punctuation ([.,;:]+).
#   - Take first whitespace-delimited token.
#   - Case-insensitive compare against basename($project_path) — Bash 3 `tr`
#     lowercase (no `${var,,}`).
#
# Module-level cache: programme.md is read ONCE per process. Self-test exposes
# `_portfolio_ceo_reset` to invalidate the cache between fixture rewrites.

_PORTFOLIO_CEO_CACHE=""        # cached extracted slug (empty = no directive)
_PORTFOLIO_CEO_CACHED=0        # 1 = cache populated (read attempted)

# _portfolio_ceo_load — read programme.md once; populate cache.
_portfolio_ceo_load() {
  [[ "$_PORTFOLIO_CEO_CACHED" == "1" ]] && return 0
  _PORTFOLIO_CEO_CACHED=1
  local pmd="${ARK_PROGRAMME_MD:-$HOME/vaults/StrategixMSPDocs/programme.md}"
  [[ ! -f "$pmd" ]] && return 0
  local extracted
  extracted=$(awk '
    /^##[[:space:]]+Next[[:space:]]+Priority[[:space:]]*$/ { found=1; next }
    found && /^##[[:space:]]/ { exit }
    found {
      # strip leading whitespace + bullet markers ("- " / "* ")
      sub(/^[[:space:]]*[-*][[:space:]]*/, "")
      sub(/^[[:space:]]+/, "")
      if ($0 == "") next
      if (substr($0, 1, 1) == "#") next
      n = split($0, parts, /[[:space:]]+/)
      if (n > 0 && parts[1] != "") {
        gsub(/[.,;:]+$/, "", parts[1])
        print parts[1]
        exit
      }
    }
  ' "$pmd" 2>/dev/null)
  # Bash 3 lowercase
  _PORTFOLIO_CEO_CACHE=$(echo "$extracted" | tr 'A-Z' 'a-z')
}

# _portfolio_ceo_reset — invalidate cache (test seam).
_portfolio_ceo_reset() {
  _PORTFOLIO_CEO_CACHE=""
  _PORTFOLIO_CEO_CACHED=0
}

# _portfolio_ceo_priority <project_path> — echo 1 if basename matches the CEO
# directive in programme.md, else 0.
_portfolio_ceo_priority() {
  local proj="$1"
  _portfolio_ceo_load
  if [[ -z "$_PORTFOLIO_CEO_CACHE" ]]; then
    echo 0
    return 0
  fi
  local base
  base=$(basename "$proj" | tr 'A-Z' 'a-z')
  if [[ "$base" == "$_PORTFOLIO_CEO_CACHE" ]]; then
    echo 1
  else
    echo 0
  fi
}
# === END SECTION: ceo-directive ===

# === SECTION: audit-and-cooldown (Plan 05-04) ===
# Plan 05-04 owns this region. Adds 24h backoff filter against
# _policy_log "portfolio" DEFERRED_* history (sqlite3 query against
# observability/policy.db). Expands portfolio_decide() to emit all 4
# decision classes correctly.
#
# Single-writer rule preserved: cool-down ONLY reads policy.db; all writes
# go through _policy_log. Function redefinitions below override the 05-01
# stubs (bash last-definition-wins) without touching 05-01's code region.

# _portfolio_row_to_json <tsv_row> — serialize 8-field TSV row to JSON ctx.
# Escapes backslash and double-quote in string fields. Numeric fields
# (stuckness, falling_health, budget_headroom, ceo_priority, total) are
# emitted as bare numbers — assumed already integers from scoring.
_portfolio_row_to_json() {
  local row="$1"
  awk -F'\t' '{
    p=$1;  gsub(/\\/, "\\\\", p);  gsub(/"/, "\\\"", p)
    c=$2;  gsub(/\\/, "\\\\", c);  gsub(/"/, "\\\"", c)
    ph=$3; gsub(/\\/, "\\\\", ph); gsub(/"/, "\\\"", ph)
    printf "{\"path\":\"%s\",\"customer\":\"%s\",\"phase\":\"%s\",\"stuckness\":%s,\"falling_health\":%s,\"budget_headroom\":%s,\"ceo_priority\":%s,\"total\":%s}", p, c, ph, $4, $5, $6, $7, $8
  }' <<< "$row"
}

# _portfolio_recently_deferred <project_path> <reason_class>
# reason_class is "BUDGET" | "HEALTHY" (matches DEFERRED_<class> in audit log).
# Returns 0 (true / cooled down) if a class=portfolio decision=DEFERRED_<class>
# row exists for this project_path within the last 24h.
# Reads $ARK_POLICY_DB or $ARK_HOME/observability/policy.db.
# Graceful degradation: missing DB / missing sqlite3 → return 1 (not cooled).
_portfolio_recently_deferred() {
  local proj="$1"
  local reason_class="$2"
  local db="${ARK_POLICY_DB:-${ARK_HOME:-$HOME/vaults/ark}/observability/policy.db}"
  [[ ! -f "$db" ]] && return 1
  command -v sqlite3 >/dev/null 2>&1 || return 1
  # 24h cutoff in ISO 8601 (BSD `date -v` first, GNU `date -d` fallback).
  local cutoff
  cutoff=$(date -u -v-24H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
           || date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
           || echo "")
  [[ -z "$cutoff" ]] && return 1
  # SQL injection defence: escape single quotes by doubling.
  local e_proj e_class
  e_proj=$(printf '%s' "$proj" | sed "s/'/''/g")
  e_class=$(printf '%s' "$reason_class" | sed "s/'/''/g")
  local count
  count=$(sqlite3 "$db" \
    "SELECT COUNT(*) FROM decisions
     WHERE class='portfolio'
       AND decision='DEFERRED_${e_class}'
       AND ts >= '$cutoff'
       AND context LIKE '%\"path\":\"$e_proj\"%';" 2>/dev/null)
  case "$count" in ''|*[!0-9]*) count=0 ;; esac
  [[ "$count" -gt 0 ]] && return 0
  return 1
}

# Override 05-01's portfolio_pick_winner to add cool-down filtering.
# Same contract: echoes winning project path or "" (exit 0). The new logic:
#   1. Score every candidate.
#   2. Skip rows with budget_headroom == 0 (Plan 05-02 budget filter).
#   3. Skip rows recently DEFERRED_BUDGET / DEFERRED_HEALTHY in the last 24h.
#   4. Sort by total desc, mtime desc; head -1.
portfolio_pick_winner() {
  local root="${1:-$ARK_PORTFOLIO_ROOT}"
  local candidates
  candidates=$(portfolio_scan_candidates "$root")
  [[ -z "$candidates" ]] && { echo ""; return 0; }

  local tmp
  tmp=$(mktemp -t ark-portfolio-pick.XXXXXX)
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    local row
    row=$(portfolio_score_project "$p" 2>/dev/null)
    [[ -z "$row" ]] && continue
    local hr stk fh cp total path mt
    hr=$(echo "$row"    | awk -F'\t' '{print $6}')
    stk=$(echo "$row"   | awk -F'\t' '{print $4}')
    fh=$(echo "$row"    | awk -F'\t' '{print $5}')
    cp=$(echo "$row"    | awk -F'\t' '{print $7}')
    total=$(echo "$row" | awk -F'\t' '{print $8}')
    path=$(echo "$row"  | awk -F'\t' '{print $1}')

    # Plan 05-02 budget filter: headroom 0 → skip (DEFERRED_BUDGET territory).
    if [[ "$hr" -le 0 ]] 2>/dev/null; then
      # Plan 05-04: cool-down filter (BUDGET) — skip if recently DEFERRED_BUDGET.
      _portfolio_recently_deferred "$path" "BUDGET" && continue
      # Even when not cooled, headroom=0 still means "don't pick" this run;
      # decide() will emit DEFERRED_BUDGET separately. Exclude from winner pool.
      continue
    fi

    # Plan 05-04: cool-down filter (HEALTHY) — projects with no actionable
    # signals (stk=0, fh=0, cp=0) recently logged as DEFERRED_HEALTHY are
    # skipped to prevent rotation spam.
    if [[ "$stk" == "0" ]] && [[ "$fh" == "0" ]] && [[ "$cp" == "0" ]]; then
      _portfolio_recently_deferred "$path" "HEALTHY" && continue
    fi

    mt=$(_portfolio_mtime "$path/.planning/STATE.md")
    printf '%s\t%s\t%s\n' "$total" "$mt" "$path" >> "$tmp"
  done <<EOF_CAND
$candidates
EOF_CAND

  local winner=""
  if [[ -s "$tmp" ]]; then
    winner=$(sort -t $'\t' -k1,1nr -k2,2nr "$tmp" | head -1 | awk -F'\t' '{print $3}')
  fi
  rm -f "$tmp"
  echo "$winner"
}

# Override 05-01's portfolio_decide stub with the production version.
# Emits all 4 decision classes:
#   NO_CANDIDATE_AVAILABLE — empty portfolio (no STATE.md anywhere).
#   DEFERRED_BUDGET        — one audit row PER over-cap candidate (headroom=0).
#   DEFERRED_HEALTHY       — no actionable signals across remaining candidates.
#   SELECTED               — winner picked; full TSV→JSON breakdown in ctx.
# Echoes winner path on stdout (or empty on deferred / no-candidate paths).
portfolio_decide() {
  local root="${1:-$ARK_PORTFOLIO_ROOT}"

  # Score every candidate up-front (cheap; 05-01 confirmed sub-second on 3-proj fixtures).
  local rows="" path row
  while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    row=$(portfolio_score_project "$path" 2>/dev/null)
    [[ -z "$row" ]] && continue
    rows+="$row"$'\n'
  done < <(portfolio_scan_candidates "$root")

  # Empty portfolio → NO_CANDIDATE_AVAILABLE.
  if [[ -z "${rows//[[:space:]]/}" ]]; then
    _policy_log "portfolio" "NO_CANDIDATE_AVAILABLE" \
      "no_projects_under_${root}" \
      "{\"root\":\"$root\"}" >/dev/null
    echo ""
    return 0
  fi

  # Emit DEFERRED_BUDGET audit per over-cap candidate (headroom=0).
  # This documents the budget filter; pick_winner already excludes them.
  local hr p ctx
  while IFS= read -r row; do
    [[ -z "$row" ]] && continue
    hr=$(echo "$row" | awk -F'\t' '{print $6}')
    if [[ "$hr" == "0" ]]; then
      p=$(echo "$row" | awk -F'\t' '{print $1}')
      # Cool-down: don't re-log DEFERRED_BUDGET if logged in last 24h.
      if ! _portfolio_recently_deferred "$p" "BUDGET"; then
        ctx=$(_portfolio_row_to_json "$row")
        _policy_log "portfolio" "DEFERRED_BUDGET" \
          "customer_over_80pct_monthly_cap" "$ctx" >/dev/null
      fi
    fi
  done <<< "$rows"

  # Pick winner (applies budget + cool-down filters via overridden pick_winner).
  local winner
  winner=$(portfolio_pick_winner "$root")

  if [[ -z "$winner" ]]; then
    # No winner. Two sub-cases:
    #   (a) all candidates over-budget → already DEFERRED_BUDGET above; emit
    #       NO_CANDIDATE_AVAILABLE so caller knows nothing to run.
    #   (b) candidates exist with headroom but no actionable signals →
    #       DEFERRED_HEALTHY for the top-scoring healthy row.
    local best_healthy
    best_healthy=$(echo "$rows" \
      | awk -F'\t' 'NF==8 && $6 != "0" {print}' \
      | sort -t $'\t' -k8,8nr | head -1)
    if [[ -n "$best_healthy" ]]; then
      local hpath
      hpath=$(echo "$best_healthy" | awk -F'\t' '{print $1}')
      if ! _portfolio_recently_deferred "$hpath" "HEALTHY"; then
        ctx=$(_portfolio_row_to_json "$best_healthy")
        _policy_log "portfolio" "DEFERRED_HEALTHY" \
          "no_actionable_signals" "$ctx" >/dev/null
      fi
    else
      _policy_log "portfolio" "NO_CANDIDATE_AVAILABLE" \
        "all_candidates_filtered_budget_or_cooldown" \
        "{\"root\":\"$root\"}" >/dev/null
    fi
    echo ""
    return 0
  fi

  # SELECTED — serialize winning row's full breakdown.
  local winning_row
  winning_row=$(echo "$rows" | awk -F'\t' -v p="$winner" '$1 == p {print; exit}')
  ctx=$(_portfolio_row_to_json "$winning_row")
  local total
  total=$(echo "$winning_row" | awk -F'\t' '{print $8}')
  _policy_log "portfolio" "SELECTED" \
    "highest_priority_total=${total}" "$ctx" >/dev/null
  echo "$winner"
}
# === END SECTION: audit-and-cooldown ===

# === Self-test (only when run directly with $1=test) ===
if [[ "${BASH_SOURCE[0]}" == "${0}" ]] && [[ "${1:-}" == "test" ]]; then
  echo "🧪 ark-portfolio-decide.sh self-test"
  echo ""

  pass=0
  fail=0
  assert_eq() {
    local expected="$1" actual="$2" label="$3"
    if [[ "$expected" == "$actual" ]]; then
      echo "  ✅ $label"
      pass=$((pass + 1))
    else
      echo "  ❌ $label  (expected: '$expected', got: '$actual')"
      fail=$((fail + 1))
    fi
  }
  assert_match() {
    local pattern="$1" actual="$2" label="$3"
    if echo "$actual" | grep -qE "$pattern"; then
      echo "  ✅ $label"
      pass=$((pass + 1))
    else
      echo "  ❌ $label  (pattern: $pattern, got: '$actual')"
      fail=$((fail + 1))
    fi
  }
  assert_true() {
    local cond_msg="$1"; shift
    if "$@"; then
      echo "  ✅ $cond_msg"; pass=$((pass + 1))
    else
      echo "  ❌ $cond_msg"; fail=$((fail + 1))
    fi
  }

  # Capture real DB md5 BEFORE any test action — must be unchanged at end.
  REAL_DB="$HOME/vaults/ark/observability/policy.db"
  REAL_DB_MD5_BEFORE=""
  if [[ -f "$REAL_DB" ]]; then
    REAL_DB_MD5_BEFORE=$(md5 -q "$REAL_DB" 2>/dev/null || md5sum "$REAL_DB" 2>/dev/null | awk '{print $1}')
  fi

  # Isolated fixture
  TMP_BASE=$(mktemp -d -t ark-portfolio-test.XXXXXX)
  trap 'rm -rf "$TMP_BASE"' EXIT

  TMP_VAULT="$TMP_BASE/vault"
  TMP_PORT="$TMP_BASE/portfolio"
  mkdir -p "$TMP_VAULT/observability" "$TMP_PORT"

  # Project A: Phase 2, fresh, no customer (scratch)
  mkdir -p "$TMP_PORT/proj-a/.planning"
  cat > "$TMP_PORT/proj-a/.planning/STATE.md" <<'EOFA'
# Proj A
Current Phase: Phase 2
status: active
EOFA

  # Project B: Phase 4, mtime > 7 days old, customer=acme
  mkdir -p "$TMP_PORT/proj-b/.planning"
  cat > "$TMP_PORT/proj-b/.planning/STATE.md" <<'EOFB'
# Proj B
Current Phase: Phase 4
status: active
EOFB
  cat > "$TMP_PORT/proj-b/.planning/policy.yml" <<'EOFBP'
bootstrap.customer: acme
EOFBP
  # Backdate STATE.md by 10 days: macOS first, GNU fallback.
  if ! touch -t "$(date -v -10d +%Y%m%d0000 2>/dev/null)" "$TMP_PORT/proj-b/.planning/STATE.md" 2>/dev/null; then
    touch -d "10 days ago" "$TMP_PORT/proj-b/.planning/STATE.md" 2>/dev/null
  fi

  # Project C: Phase 1, blocked, customer=beta
  mkdir -p "$TMP_PORT/proj-c/.planning"
  cat > "$TMP_PORT/proj-c/.planning/STATE.md" <<'EOFC'
# Proj C
Current Phase: Phase 1
status: blocked
EOFC
  cat > "$TMP_PORT/proj-c/.planning/policy.yml" <<'EOFCP'
bootstrap.customer: beta
EOFCP

  # Activate test environment
  export ARK_HOME="$TMP_VAULT"
  export ARK_PORTFOLIO_ROOT="$TMP_PORT"

  echo "Discovery:"
  scan_out=$(portfolio_scan_candidates "$TMP_PORT")
  scan_count=$(echo "$scan_out" | grep -c .)
  assert_eq "3" "$scan_count" "portfolio_scan_candidates finds 3 projects"

  echo ""
  echo "Customer attribution:"
  assert_eq "scratch" "$(_portfolio_read_customer "$TMP_PORT/proj-a")" "proj-a → scratch (no policy.yml)"
  assert_eq "acme"    "$(_portfolio_read_customer "$TMP_PORT/proj-b")" "proj-b → acme"
  assert_eq "beta"    "$(_portfolio_read_customer "$TMP_PORT/proj-c")" "proj-c → beta"

  echo ""
  echo "Stuckness:"
  assert_eq "0" "$(_portfolio_stuckness "$TMP_PORT/proj-a")" "proj-a → 0 (fresh, active)"
  assert_eq "1" "$(_portfolio_stuckness "$TMP_PORT/proj-b")" "proj-b → 1 (>7d stale)"
  assert_eq "2" "$(_portfolio_stuckness "$TMP_PORT/proj-c")" "proj-c → 2 (status: blocked)"

  echo ""
  echo "Scoring:"
  row_a=$(portfolio_score_project "$TMP_PORT/proj-a")
  field_count=$(echo "$row_a" | awk -F'\t' '{print NF}')
  assert_eq "8" "$field_count" "portfolio_score_project emits 8 TSV fields"

  row_c=$(portfolio_score_project "$TMP_PORT/proj-c")
  total_c=$(echo "$row_c" | awk -F'\t' '{print $8}')
  if [[ "$total_c" -ge 6 ]] 2>/dev/null; then
    pass=$((pass + 1)); echo "  ✅ proj-c total ≥ 6 (stuckness=2 → 2*3=6, got $total_c)"
  else
    fail=$((fail + 1)); echo "  ❌ proj-c total ≥ 6 (got $total_c)"
  fi

  echo ""
  echo "Winner selection:"
  winner=$(portfolio_pick_winner "$TMP_PORT")
  assert_eq "$TMP_PORT/proj-c" "$winner" "winner = proj-c (highest score, blocked)"

  echo ""
  echo "Tie-break (most-recently-touched wins when totals tie):"
  # Make all projects clean & equal-priority by clearing C's blocked status
  cat > "$TMP_PORT/proj-c/.planning/STATE.md" <<'EOFCC'
# Proj C
Current Phase: Phase 1
status: active
EOFCC
  # Touch B and A fresh so all three have identical (zero) score.
  touch "$TMP_PORT/proj-a/.planning/STATE.md"
  touch "$TMP_PORT/proj-b/.planning/STATE.md"
  # Make A the most-recently-touched: ensure ordering by sleeping or `touch -t`.
  sleep 1
  touch "$TMP_PORT/proj-a/.planning/STATE.md"
  winner_tied=$(portfolio_pick_winner "$TMP_PORT")
  assert_eq "$TMP_PORT/proj-a" "$winner_tied" "tie-break → proj-a (most-recently-touched)"

  echo ""
  echo "Empty portfolio:"
  EMPTY_PORT=$(mktemp -d -t ark-portfolio-empty.XXXXXX)
  empty_winner=$(portfolio_pick_winner "$EMPTY_PORT")
  empty_rc=$?
  assert_eq "" "$empty_winner" "empty portfolio → empty stdout"
  assert_eq "0" "$empty_rc"     "empty portfolio → exit 0"
  rm -rf "$EMPTY_PORT"

  echo ""
  echo "portfolio_decide audit log:"
  # Stub _policy_log to capture invocations into a file.
  POL_CAPTURE="$TMP_BASE/policy-calls.log"
  : > "$POL_CAPTURE"
  _real_policy_log_save=$(declare -f _policy_log)
  _policy_log() {
    echo "class=$1 decision=$2 reason=$3 context=${4:-null}" >> "$POL_CAPTURE"
    echo "stub-id"
  }
  decide_out=$(portfolio_decide "$TMP_PORT")
  if grep -q 'class=portfolio decision=SELECTED' "$POL_CAPTURE"; then
    pass=$((pass + 1)); echo "  ✅ portfolio_decide invoked _policy_log class=portfolio decision=SELECTED"
  else
    fail=$((fail + 1)); echo "  ❌ portfolio_decide did not log SELECTED"
    echo "    capture: $(cat "$POL_CAPTURE")"
  fi
  # Restore _policy_log
  eval "$_real_policy_log_save"

  echo ""
  echo "Bash-3 compat regressions:"
  if head -300 "$0" | grep -qE '^[[:space:]]*(declare|local)[[:space:]]+-A'; then
    fail=$((fail + 1)); echo "  ❌ uses associative arrays (Bash 4 only)"
  else
    pass=$((pass + 1)); echo "  ✅ no associative arrays in main code"
  fi
  # Exclude commented lines (header rules document the prohibition).
  if head -300 "$0" | grep -nE 'read[[:space:]]+-p' | grep -vE '^[0-9]+:[[:space:]]*#' >/dev/null; then
    fail=$((fail + 1)); echo "  ❌ contains 'read -p' in delivery-path"
  else
    pass=$((pass + 1)); echo "  ✅ no 'read -p' in delivery-path"
  fi

  echo ""
  echo "Sentinel sections present (load-bearing for Wave-2 parallel work):"
  for sec in "budget-reader" "ceo-directive" "audit-and-cooldown"; do
    if grep -qE "^# === SECTION: $sec " "$0" && grep -qE "^# === END SECTION: $sec ===" "$0"; then
      pass=$((pass + 1)); echo "  ✅ SECTION: $sec present (open + close)"
    else
      fail=$((fail + 1)); echo "  ❌ SECTION: $sec missing or malformed"
    fi
  done

  echo ""
  echo "Plan 05-02 budget-reader assertions:"
  # Set up mock customer policy.yml files inside the test vault.
  # ARK_HOME is already exported = $TMP_VAULT, so the cascade resolves
  # ARK_HOME/customers/<slug>/policy.yml as the customer layer.
  mkdir -p "$TMP_VAULT/customers/acme"
  cat > "$TMP_VAULT/customers/acme/policy.yml" <<'EOF_ACME'
budget.monthly_used: 90000
budget.monthly_cap: 100000
EOF_ACME
  mkdir -p "$TMP_VAULT/customers/beta"
  cat > "$TMP_VAULT/customers/beta/policy.yml" <<'EOF_BETA'
budget.monthly_used: 10000
budget.monthly_cap: 100000
EOF_BETA
  # Defensive: clear potential outer-shell env shadows of the resolved keys.
  unset ARK_BUDGET_MONTHLY_USED ARK_BUDGET_MONTHLY_CAP

  # acme: 90% used → ≥80% threshold → headroom 0
  assert_eq "0"   "$(_portfolio_budget_headroom acme)"    "acme over 80% returns headroom 0"
  # beta: 10% used → headroom 90
  assert_eq "90"  "$(_portfolio_budget_headroom beta)"    "beta at 10% returns headroom 90"
  # scratch: no customer file → headroom 100
  assert_eq "100" "$(_portfolio_budget_headroom scratch)" "scratch returns headroom 100"

  # Score recomputation: proj-b (acme) over 80% must reflect budget_headroom=0.
  # First restore proj-b's blocked/stale state was wiped by tie-break test;
  # we just need proj-b's customer to still be acme (policy.yml untouched).
  row_b_post=$(portfolio_score_project "$TMP_PORT/proj-b")
  hr_b_post=$(echo "$row_b_post" | awk -F'\t' '{print $6}')
  assert_eq "0" "$hr_b_post" "portfolio_score_project proj-b reflects budget_headroom=0 after over-cap"

  # Bonus: _portfolio_global_fair_share — divides remaining global cap by N.
  # No vault policy.yml present → defaults: cap_total=1000000, used_total=0.
  fs=$(_portfolio_global_fair_share 4)
  assert_eq "250000" "$fs" "_portfolio_global_fair_share 4 → 250000 (default 1M / 4)"

  echo ""
  echo "Plan 05-03 ceo-directive assertions:"
  # Fixture programme.md: heading present, value = proj-a (vanilla form)
  PMD="$TMP_BASE/programme.md"
  cat > "$PMD" <<'EOF_PMD1'
# Programme

## Other Section
blah

## Next Priority

proj-a

## Tail
EOF_PMD1
  export ARK_PROGRAMME_MD="$PMD"
  _portfolio_ceo_reset
  assert_eq "1" "$(_portfolio_ceo_priority "$TMP_PORT/proj-a")" "ceo directive matches proj-a"
  assert_eq "0" "$(_portfolio_ceo_priority "$TMP_PORT/proj-b")" "ceo directive does not match proj-b"

  # Missing programme.md → 0 for everyone
  export ARK_PROGRAMME_MD="$TMP_BASE/no-such-file.md"
  _portfolio_ceo_reset
  assert_eq "0" "$(_portfolio_ceo_priority "$TMP_PORT/proj-a")" "missing programme.md returns 0"

  # Bullet form with trailing punctuation: "- proj-c."
  cat > "$PMD" <<'EOF_PMD2'
## Next Priority
- proj-c.

## Other
EOF_PMD2
  export ARK_PROGRAMME_MD="$PMD"
  _portfolio_ceo_reset
  assert_eq "1" "$(_portfolio_ceo_priority "$TMP_PORT/proj-c")" "bullet+punctuation form parses to proj-c"

  # Score row reflects ceo_priority=1 when directive set
  cat > "$PMD" <<'EOF_PMD3'
## Next Priority
proj-a
EOF_PMD3
  export ARK_PROGRAMME_MD="$PMD"
  _portfolio_ceo_reset
  row_a_ceo=$(portfolio_score_project "$TMP_PORT/proj-a")
  ceo_a=$(echo "$row_a_ceo" | awk -F'\t' '{print $7}')
  assert_eq "1" "$ceo_a" "score row reflects ceo_priority=1 for proj-a"

  # Reset directive env so it doesn't bleed into later tests
  unset ARK_PROGRAMME_MD
  _portfolio_ceo_reset

  echo ""
  echo "Plan 05-04 audit-and-cooldown assertions:"
  # Re-stub _policy_log to capture all calls into a fresh log file.
  LOG_CAP="$TMP_BASE/audit_capture.txt"
  : > "$LOG_CAP"
  _real_policy_log_save2=$(declare -f _policy_log)
  _policy_log() {
    echo "class=$1 decision=$2 reason=$3 context=${4:-null}" >> "$LOG_CAP"
    echo "stub-id-$$"
  }

  # Reset CEO directive (bleeds in from prior assertions); ensure no programme.md.
  unset ARK_PROGRAMME_MD
  _portfolio_ceo_reset

  # Set up isolated mock policy.db for cool-down queries.
  MOCK_DB="$TMP_VAULT/observability/policy.db"
  mkdir -p "$(dirname "$MOCK_DB")"
  sqlite3 "$MOCK_DB" "CREATE TABLE decisions (decision_id TEXT PRIMARY KEY, ts TEXT NOT NULL, schema_version INTEGER NOT NULL DEFAULT 1, class TEXT NOT NULL, decision TEXT NOT NULL, reason TEXT NOT NULL, context TEXT, outcome TEXT, correlation_id TEXT);"
  export ARK_POLICY_DB="$MOCK_DB"

  # Test 1: portfolio_decide on a 3-proj fixture (acme=over budget, beta=fresh, scratch=fresh)
  # → emits SELECTED for non-acme winner AND DEFERRED_BUDGET for acme proj-b.
  : > "$LOG_CAP"
  decide_winner=$(portfolio_decide "$TMP_PORT")
  if grep -q 'class=portfolio decision=DEFERRED_BUDGET' "$LOG_CAP"; then
    pass=$((pass + 1)); echo "  ✅ over-budget customer (acme) emits DEFERRED_BUDGET"
  else
    fail=$((fail + 1)); echo "  ❌ no DEFERRED_BUDGET in log"
    echo "    capture: $(cat "$LOG_CAP")"
  fi
  if grep -q 'class=portfolio decision=SELECTED' "$LOG_CAP"; then
    pass=$((pass + 1)); echo "  ✅ healthy candidate (beta or scratch) emits SELECTED"
  else
    fail=$((fail + 1)); echo "  ❌ no SELECTED in log"
  fi
  # Context_json must contain full breakdown (total field).
  if grep -q '"total":' "$LOG_CAP"; then
    pass=$((pass + 1)); echo "  ✅ context_json contains total field (full breakdown)"
  else
    fail=$((fail + 1)); echo "  ❌ context_json missing total field"
  fi

  # Test 2: Empty portfolio → NO_CANDIDATE_AVAILABLE
  EMPTY2=$(mktemp -d -t ark-portfolio-empty04.XXXXXX)
  : > "$LOG_CAP"
  portfolio_decide "$EMPTY2" >/dev/null
  if grep -q 'class=portfolio decision=NO_CANDIDATE_AVAILABLE' "$LOG_CAP"; then
    pass=$((pass + 1)); echo "  ✅ empty portfolio emits NO_CANDIDATE_AVAILABLE"
  else
    fail=$((fail + 1)); echo "  ❌ empty portfolio did not emit NO_CANDIDATE_AVAILABLE"
  fi
  rm -rf "$EMPTY2"

  # Test 3: Cool-down — recently DEFERRED_BUDGET row blocks re-detection.
  PROJB_PATH="$TMP_PORT/proj-b"
  NOW_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  sqlite3 "$MOCK_DB" "DELETE FROM decisions;"
  sqlite3 "$MOCK_DB" "INSERT INTO decisions (decision_id, ts, schema_version, class, decision, reason, context) VALUES ('test-recent', '$NOW_ISO', 1, 'portfolio', 'DEFERRED_BUDGET', 'r', '{\"path\":\"$PROJB_PATH\"}');"
  if _portfolio_recently_deferred "$PROJB_PATH" "BUDGET"; then
    pass=$((pass + 1)); echo "  ✅ cool-down detects DEFERRED_BUDGET within 24h"
  else
    fail=$((fail + 1)); echo "  ❌ cool-down missed recent DEFERRED_BUDGET"
  fi

  # Test 4: Cool-down — 25h-old row should NOT match.
  sqlite3 "$MOCK_DB" "DELETE FROM decisions;"
  OLD_ISO=$(date -u -v-25H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
            || date -u -d '25 hours ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
  sqlite3 "$MOCK_DB" "INSERT INTO decisions (decision_id, ts, schema_version, class, decision, reason, context) VALUES ('test-old', '$OLD_ISO', 1, 'portfolio', 'DEFERRED_BUDGET', 'r', '{\"path\":\"$PROJB_PATH\"}');"
  if _portfolio_recently_deferred "$PROJB_PATH" "BUDGET"; then
    fail=$((fail + 1)); echo "  ❌ cool-down should not match >24h-old row"
  else
    pass=$((pass + 1)); echo "  ✅ cool-down correctly ignores >24h-old row"
  fi

  # Test 5: Recently-deferred project skipped from candidate pool by pick_winner.
  # Insert a recent DEFERRED_BUDGET for proj-c (currently the would-be winner if its
  # customer were healthy). Make proj-c look acme-budget-healthy first by swapping
  # its customer to a fresh slug, then verify it gets skipped via cool-down on
  # HEALTHY class instead.
  sqlite3 "$MOCK_DB" "DELETE FROM decisions;"
  PROJC_PATH="$TMP_PORT/proj-c"
  # Make proj-c "healthy" (active, not blocked, no falling health, scratch customer).
  cat > "$TMP_PORT/proj-c/.planning/STATE.md" <<'EOFCH'
# Proj C
Current Phase: Phase 1
status: active
EOFCH
  rm -f "$TMP_PORT/proj-c/.planning/policy.yml"  # → scratch (headroom 100)
  # Log a HEALTHY deferral for proj-c within 24h.
  sqlite3 "$MOCK_DB" "INSERT INTO decisions (decision_id, ts, schema_version, class, decision, reason, context) VALUES ('test-healthy', '$NOW_ISO', 1, 'portfolio', 'DEFERRED_HEALTHY', 'r', '{\"path\":\"$PROJC_PATH\"}');"
  # Now pick_winner should skip proj-c (cooled HEALTHY); among remaining
  # candidates, proj-a (scratch, fresh, no signals) wins via tie-break.
  cooled_winner=$(portfolio_pick_winner "$TMP_PORT")
  if [[ "$cooled_winner" != "$PROJC_PATH" ]]; then
    pass=$((pass + 1)); echo "  ✅ recently DEFERRED_HEALTHY project skipped from pool (winner=$(basename "$cooled_winner"))"
  else
    fail=$((fail + 1)); echo "  ❌ cooled-down proj-c was selected as winner"
  fi

  # Test 6: All 4 decision classes appear as string literals in the file.
  classes_found=0
  for cls in "SELECTED" "DEFERRED_BUDGET" "DEFERRED_HEALTHY" "NO_CANDIDATE_AVAILABLE"; do
    if grep -q "\"$cls\"" "$0"; then
      classes_found=$((classes_found + 1))
    fi
  done
  assert_eq "4" "$classes_found" "all 4 decision classes present as string literals"

  # Test 7: _portfolio_row_to_json produces valid JSON.
  sample_row=$(portfolio_score_project "$TMP_PORT/proj-a")
  sample_ctx=$(_portfolio_row_to_json "$sample_row")
  if command -v python3 >/dev/null 2>&1; then
    if python3 -c "import json,sys; json.loads(sys.argv[1])" "$sample_ctx" 2>/dev/null; then
      pass=$((pass + 1)); echo "  ✅ _portfolio_row_to_json produces valid JSON"
    else
      fail=$((fail + 1)); echo "  ❌ _portfolio_row_to_json invalid JSON: $sample_ctx"
    fi
  else
    if echo "$sample_ctx" | grep -qE '^\{.*"total":[0-9]+\}$'; then
      pass=$((pass + 1)); echo "  ✅ _portfolio_row_to_json shape ok (no python3 available)"
    else
      fail=$((fail + 1)); echo "  ❌ _portfolio_row_to_json shape bad"
    fi
  fi

  # Test 8: Single-writer rule — no inline INSERT INTO decisions outside self-test.
  # Self-test starts at the line containing 'BASH_SOURCE[0]' guard.
  selftest_start=$(grep -n 'BASH_SOURCE\[0\]\}.*\${0}' "$0" | head -1 | awk -F: '{print $1}')
  prod_inserts=$(awk -v end="$selftest_start" 'NR < end && /INSERT[[:space:]]+INTO[[:space:]]+decisions/' "$0" | wc -l | tr -d ' ')
  assert_eq "0" "$prod_inserts" "no INSERT INTO decisions in production code (single-writer rule)"

  # Restore real _policy_log and unset ARK_POLICY_DB.
  eval "$_real_policy_log_save2"
  unset ARK_POLICY_DB

  echo ""
  echo "Real-DB isolation (no writes to ~/vaults/ark/observability/policy.db):"
  if [[ -n "$REAL_DB_MD5_BEFORE" ]]; then
    REAL_DB_MD5_AFTER=$(md5 -q "$REAL_DB" 2>/dev/null || md5sum "$REAL_DB" 2>/dev/null | awk '{print $1}')
    assert_eq "$REAL_DB_MD5_BEFORE" "$REAL_DB_MD5_AFTER" "real policy.db md5 unchanged before/after self-test"
  else
    pass=$((pass + 1)); echo "  ✅ real policy.db absent — vacuously isolated"
  fi

  echo ""
  if [[ "$fail" -eq 0 ]]; then
    echo "✅ ALL PORTFOLIO-DECIDE TESTS PASSED ($pass/$pass)"
    exit 0
  else
    echo "❌ $fail/$((pass+fail)) tests failed"
    exit 1
  fi
fi
