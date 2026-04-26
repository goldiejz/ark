#!/usr/bin/env bash
# ark-dashboard.sh — Tier A pull-style CEO dashboard for AOS Phase 6.5
#
# Read-only over policy.db, ESCALATIONS.md, vault docs, per-project STATE.md.
# Prints 7 colored sections in <2s and exits.
#
# Sections (priority order):
#   1. Portfolio grid       — projects × phase × last activity × health
#   2. Escalations panel    — pending blockers by class
#   3. Budget summary       — per-customer monthly burn, headroom
#   4. Recent decisions     — last 50 rows from policy.db
#   5. Learning watch       — recent promotions + universal-patterns count
#   6. Drift detector       — STATE.md vs newest phase dir
#   7. Tier health          — last verify report's pass/fail per tier
#
# Usage:
#   bash scripts/ark-dashboard.sh
#   bash scripts/ark-dashboard.sh --no-color
#   bash scripts/ark-dashboard.sh --section <name>      # reserved; v1 ignores
#   NO_COLOR=1 bash scripts/ark-dashboard.sh
#   ARK_HOME=/tmp/empty bash scripts/ark-dashboard.sh   # graceful when vault missing
#
# Constraints (locked, see .planning/phases/06.5-ceo-dashboard/CONTEXT.md):
#   - Bash 3 compatible (macOS default).  No declare -A, no ${var,,}.
#   - READ-ONLY: never writes to policy.db, ESCALATIONS.md, or any vault file.
#   - Every sqlite3 call uses -readonly (defense in depth).
#   - No `read -p` anywhere (delivery-path discipline; Tier 13 will regress this).
#   - Color degrades gracefully (NO_COLOR=1 or tput colors < 8).
#
# Phase 6.5 — REQ-DASH-01..REQ-DASH-04 covered by this plan (06.5-01).

set -uo pipefail   # NOT -e — section renderers must tolerate partial data

# ============================================================================
# Data-source resolution
# ============================================================================
VAULT_PATH="${ARK_HOME:-$HOME/vaults/ark}"
POLICY_DB="${ARK_POLICY_DB:-$VAULT_PATH/observability/policy.db}"
PORTFOLIO_ROOT="${ARK_PORTFOLIO_ROOT:-$HOME/code}"
ESCALATIONS_FILE="$VAULT_PATH/ESCALATIONS.md"
VERIFY_REPORTS_DIR="$VAULT_PATH/observability/verification-reports"
UNIVERSAL_PATTERNS="$VAULT_PATH/lessons/universal-patterns.md"
ANTI_PATTERNS="$VAULT_PATH/bootstrap/anti-patterns.md"
POLICY_EVOLUTION="$VAULT_PATH/observability/policy-evolution.md"

# ============================================================================
# ANSI palette (verbatim from scripts/ark-verify.sh:41-45)
# ============================================================================
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================================
# Argument parser
# ============================================================================
SECTION_FILTER=""
FORCE_NO_COLOR=false

print_help() {
  cat <<'EOF'
ark-dashboard.sh — Tier A CEO dashboard (read-only)

Usage:
  bash scripts/ark-dashboard.sh [OPTIONS]

Options:
  --help              Show this help and exit
  --no-color          Disable ANSI color output (also: NO_COLOR=1)
  --section <name>    Filter to a single section (reserved; v1 prints all)

Environment:
  ARK_HOME            Override vault root (default: ~/vaults/ark)
  ARK_POLICY_DB       Override policy.db path
  ARK_PORTFOLIO_ROOT  Override portfolio root (default: ~/code)
  NO_COLOR            POSIX standard — set to disable color
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)     print_help; exit 0 ;;
    --no-color)    FORCE_NO_COLOR=true; shift ;;
    --section)     SECTION_FILTER="${2:-}"; shift 2 ;;
    *)             shift ;;
  esac
done

# Color-degrade guard (NO_COLOR or tput colors < 8 or --no-color)
if [[ "$FORCE_NO_COLOR" == "true" ]] || [[ -n "${NO_COLOR:-}" ]] || \
   [[ "$(tput colors 2>/dev/null || echo 0)" -lt 8 ]]; then
  GREEN=''; YELLOW=''; RED=''; BLUE=''; NC=''
fi

# ============================================================================
# Helpers
# ============================================================================
print_section_header() {
  printf "\n${BLUE}━━━ %s ━━━${NC}\n\n" "$1"
}

# db_query <sql> — wraps sqlite3 -readonly with graceful degradation.
# If POLICY_DB doesn't exist, returns empty string (and exits the function 0).
# Uses -readonly flag for defense-in-depth on the read-only invariant.
db_query() {
  local sql="$1"
  if [[ ! -f "$POLICY_DB" ]]; then
    return 0
  fi
  sqlite3 -readonly -separator '|' "$POLICY_DB" "$sql" 2>/dev/null || true
}

# Format epoch-seconds-ago as "Nh ago" / "Nd ago" / "Nm ago".
human_ago() {
  local then="$1"
  local now; now=$(date +%s)
  local diff=$(( now - then ))
  if [[ "$diff" -lt 0 ]]; then diff=0; fi
  if   [[ "$diff" -lt 60 ]];     then printf "%ds ago" "$diff"
  elif [[ "$diff" -lt 3600 ]];   then printf "%dm ago" "$(( diff / 60 ))"
  elif [[ "$diff" -lt 86400 ]];  then printf "%dh ago" "$(( diff / 3600 ))"
  else                                printf "%dd ago" "$(( diff / 86400 ))"
  fi
}

# Cross-platform mtime (BSD stat -f %m, GNU stat -c %Y).
file_mtime() {
  stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0
}

# Health color from 0-100 metric (≥80 green, ≥50 yellow, else red).
health_color() {
  local m="$1"
  if   [[ "$m" -ge 80 ]]; then printf "%s" "$GREEN"
  elif [[ "$m" -ge 50 ]]; then printf "%s" "$YELLOW"
  else                         printf "%s" "$RED"
  fi
}

# Discover projects: depth-3 walk for .planning/STATE.md.
# Outputs one path per line. Suppresses permission errors.
discover_projects() {
  if [[ ! -d "$PORTFOLIO_ROOT" ]]; then return 0; fi
  find "$PORTFOLIO_ROOT" -maxdepth 3 -type f -name STATE.md \
       -path '*/.planning/STATE.md' 2>/dev/null
}

# Parse current_phase from a STATE.md frontmatter (matches yaml convention).
parse_current_phase() {
  awk '/^current_phase:/ { sub(/^current_phase: */, ""); gsub(/"/, ""); print; exit }' "$1"
}

# ============================================================================
# Section 1 — Portfolio grid
# ============================================================================
render_portfolio_grid() {
  print_section_header "PORTFOLIO"

  local states; states="$(discover_projects)"
  if [[ -z "$states" ]]; then
    printf "${YELLOW}(no projects discovered under %s)${NC}\n" "$PORTFOLIO_ROOT"
    return 0
  fi

  printf "%-30s %-40s %-15s %s\n" "Project" "Phase" "Last activity" "Health"
  printf "%-30s %-40s %-15s %s\n" "-------" "-----" "-------------" "------"

  local now; now=$(date +%s)
  local s phase mtime ago color status proj
  while IFS= read -r s; do
    [[ -z "$s" ]] && continue
    proj="$(basename "$(dirname "$(dirname "$s")")")"
    phase="$(parse_current_phase "$s" 2>/dev/null)"
    [[ -z "$phase" ]] && phase="(unknown)"
    mtime="$(file_mtime "$s")"
    ago="$(human_ago "$mtime")"
    local diff=$(( now - mtime ))
    if   [[ "$diff" -lt 86400 ]];  then color="$GREEN"; status="✅ active"
    elif [[ "$diff" -lt 604800 ]]; then color="$YELLOW"; status="⚠ stale"
    else                                color="$RED"; status="✗ cold"
    fi
    # Truncate phase to 38 chars for alignment
    local phase_short="${phase:0:38}"
    printf "%-30s %-40s %-15s ${color}%s${NC}\n" \
      "$proj" "$phase_short" "$ago" "$status"
  done <<< "$states"
}

# ============================================================================
# Section 2 — Escalations panel
# ============================================================================
render_escalations() {
  print_section_header "ESCALATIONS"

  if [[ ! -f "$ESCALATIONS_FILE" ]]; then
    printf "${GREEN}✅ No escalations queue file (no blockers)${NC}\n"
    return 0
  fi

  local pending resolved
  pending=$(grep -c '^## \[PENDING\]' "$ESCALATIONS_FILE" 2>/dev/null || echo 0)
  resolved=$(grep -c '^## \[RESOLVED\]' "$ESCALATIONS_FILE" 2>/dev/null || echo 0)

  if [[ "$pending" -eq 0 ]]; then
    printf "${GREEN}✅ 0 pending blockers${NC}  (resolved: %s)\n" "$resolved"
    return 0
  fi

  printf "${RED}🚨 %s pending blockers${NC}  (resolved: %s)\n\n" "$pending" "$resolved"

  # Per-class counts (4 true-blocker classes).
  # We grep within each [PENDING] block for class hints. Since blocks are
  # variable-length, we count via simple substring matches in the file.
  local cls c
  for cls in budget architectural destructive repeated_failure; do
    c=$(awk -v cls="$cls" '
      /^## \[PENDING\]/ { in_p=1; matched=0 }
      /^## \[RESOLVED\]/ { in_p=0 }
      in_p && tolower($0) ~ cls && !matched { matched=1; n++ }
      END { print n+0 }
    ' "$ESCALATIONS_FILE" 2>/dev/null || echo 0)
    printf "  %-22s %s\n" "$cls" "$c"
  done

  printf "\nRecent pending IDs:\n"
  awk '/^## \[PENDING\]/ { print "  " $0 }' "$ESCALATIONS_FILE" 2>/dev/null | head -10
}

# ============================================================================
# Section 3 — Budget summary
# ============================================================================
render_budget() {
  print_section_header "BUDGET"

  local states; states="$(discover_projects)"
  if [[ -z "$states" ]]; then
    printf "${YELLOW}(no projects discovered)${NC}\n"
    return 0
  fi

  local found=0
  printf "%-30s %12s %12s %10s %s\n" "Project" "Used" "Cap" "Headroom" "Risk"
  printf "%-30s %12s %12s %10s %s\n" "-------" "----" "---" "--------" "----"

  local s budget_file proj used cap headroom_pct color status
  local total_used=0 total_cap=0
  while IFS= read -r s; do
    [[ -z "$s" ]] && continue
    proj="$(basename "$(dirname "$(dirname "$s")")")"
    budget_file="$(dirname "$s")/budget.json"
    [[ ! -f "$budget_file" ]] && continue
    found=1

    # Use python3 for JSON parsing — no jq dependency assumption.
    # Read monthly_used + monthly_cap_tokens (real schema in this vault).
    local pair
    pair=$(python3 -c '
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    used = d.get("monthly_used", d.get("monthly_used_zar", 0)) or 0
    cap  = d.get("monthly_cap_tokens", d.get("monthly_cap_zar", 0)) or 0
    print("%d %d" % (int(used), int(cap)))
except Exception:
    print("0 0")
' "$budget_file" 2>/dev/null)
    used="${pair% *}"; cap="${pair#* }"
    [[ -z "$used" ]] && used=0
    [[ -z "$cap"  ]] && cap=0

    if [[ "$cap" -le 0 ]]; then
      headroom_pct=100
    else
      # headroom% = 100 * (cap - used) / cap, clamped >= 0
      headroom_pct=$(( (cap - used) * 100 / cap ))
      [[ "$headroom_pct" -lt 0 ]] && headroom_pct=0
    fi

    if   [[ "$headroom_pct" -lt 10 ]]; then color="$RED";    status="✗ CAP"
    elif [[ "$headroom_pct" -lt 30 ]]; then color="$YELLOW"; status="⚠ tight"
    else                                    color="$GREEN";  status="✅ ok"
    fi

    total_used=$(( total_used + used ))
    total_cap=$(( total_cap + cap ))

    printf "%-30s %12d %12d %9d%% ${color}%s${NC}\n" \
      "$proj" "$used" "$cap" "$headroom_pct" "$status"
  done <<< "$states"

  if [[ "$found" -eq 0 ]]; then
    printf "${YELLOW}(no budget.json files found)${NC}\n"
    return 0
  fi

  # Aggregate footer
  local agg_pct=100
  if [[ "$total_cap" -gt 0 ]]; then
    agg_pct=$(( (total_cap - total_used) * 100 / total_cap ))
  fi
  printf -- "%-30s %12s %12s %10s\n" "-------" "----" "---" "--------"
  printf "%-30s %12d %12d %9d%%\n" "TOTAL" "$total_used" "$total_cap" "$agg_pct"
}

# ============================================================================
# Section 4 — Recent decisions stream
# ============================================================================
render_recent_decisions() {
  print_section_header "RECENT DECISIONS"

  if [[ ! -f "$POLICY_DB" ]]; then
    printf "${YELLOW}(policy.db missing — %s)${NC}\n" "$POLICY_DB"
    return 0
  fi

  local total
  total=$(db_query "SELECT COUNT(*) FROM decisions;")
  if [[ -z "$total" ]] || [[ "$total" -eq 0 ]]; then
    printf "${YELLOW}(policy.db empty — no decisions yet)${NC}\n"
    return 0
  fi

  printf "Total rows: %s    (showing last 50)\n\n" "$total"
  printf "%-22s %-18s %-22s %s\n" "Timestamp (UTC)" "Class" "Decision" "Reason"
  printf "%-22s %-18s %-22s %s\n" "---------------" "-----" "--------" "------"

  # Single indexed query — ORDER BY ts hits idx_decisions_ts.
  local rows
  rows=$(db_query "SELECT ts, class, decision, substr(reason, 1, 60) FROM decisions ORDER BY ts DESC LIMIT 50;")

  local IFS_old="$IFS"
  IFS=$'\n'
  local row ts class decision reason color
  for row in $rows; do
    [[ -z "$row" ]] && continue
    IFS='|' read -r ts class decision reason <<< "$row"
    case "$class" in
      escalation)                       color="$RED" ;;
      self_improve|lesson_promote)      color="$BLUE" ;;
      dispatch_failure)                 color="$YELLOW" ;;
      *)                                color="" ;;
    esac
    # Truncate fields for alignment. ANSI codes wrap the (already-padded)
    # class field so printf's %-Ns column-counting stays accurate (printf
    # counts the escape bytes against the width otherwise).
    local ts_short="${ts:0:19}"
    local cls_padded
    cls_padded=$(printf "%-18s" "${class:0:18}")
    local dec_short="${decision:0:22}"
    local rsn_short="${reason:0:60}"
    if [[ -n "$color" ]]; then
      printf "%-22s ${color}%s${NC} %-22s %s\n" \
        "$ts_short" "$cls_padded" "$dec_short" "$rsn_short"
    else
      printf "%-22s %s %-22s %s\n" \
        "$ts_short" "$cls_padded" "$dec_short" "$rsn_short"
    fi
  done
  IFS="$IFS_old"

  # Aggregate counts by class for the 50-row window.
  printf "\nClass breakdown (last 50):\n"
  local class_counts
  class_counts=$(db_query "
    SELECT class, COUNT(*) FROM (
      SELECT class FROM decisions ORDER BY ts DESC LIMIT 50
    ) GROUP BY class ORDER BY COUNT(*) DESC;
  ")
  IFS=$'\n'
  local cls_row cls n
  for cls_row in $class_counts; do
    [[ -z "$cls_row" ]] && continue
    IFS='|' read -r cls n <<< "$cls_row"
    printf "  %-22s %s\n" "$cls" "$n"
  done
  IFS="$IFS_old"
}

# ============================================================================
# Section 5 — Learning watch
# ============================================================================
render_learning_watch() {
  print_section_header "LEARNING WATCH"

  # Recent promotions (last 7 days)
  if [[ -f "$POLICY_DB" ]]; then
    local promotions
    promotions=$(db_query "
      SELECT ts, decision, substr(reason, 1, 50)
      FROM decisions
      WHERE class IN ('self_improve','lesson_promote')
        AND ts > datetime('now','-7 days')
      ORDER BY ts DESC LIMIT 20;
    ")
    if [[ -z "$promotions" ]]; then
      printf "${YELLOW}(no promotions in last 7 days)${NC}\n"
    else
      printf "Recent promotions (last 7 days):\n"
      printf "%-22s %-25s %s\n" "Timestamp" "Decision" "Reason"
      local IFS_old="$IFS"
      IFS=$'\n'
      local row ts dec rsn
      for row in $promotions; do
        IFS='|' read -r ts dec rsn <<< "$row"
        printf "  %-22s %-25s %s\n" "${ts:0:19}" "${dec:0:25}" "$rsn"
      done
      IFS="$IFS_old"
    fi
  else
    printf "${YELLOW}(policy.db missing)${NC}\n"
  fi

  echo ""

  # Near-threshold patterns: parse the "Mediocre" section of policy-evolution.md
  if [[ -f "$POLICY_EVOLUTION" ]]; then
    local mediocre_count
    mediocre_count=$(awk '
      /^## Mediocre/ { in_m=1; next }
      /^## / && in_m { in_m=0 }
      in_m && /^\| [a-z]/ { n++ }
      END { print n+0 }
    ' "$POLICY_EVOLUTION" 2>/dev/null)
    printf "Patterns near promotion threshold: %s\n" "${mediocre_count:-0}"
  else
    printf "${YELLOW}(policy-evolution.md missing)${NC}\n"
  fi

  # Universal & anti-pattern counts
  local up_count ap_count
  up_count=$(grep -c '^## ' "$UNIVERSAL_PATTERNS" 2>/dev/null || echo 0)
  ap_count=$(grep -c '^## ' "$ANTI_PATTERNS" 2>/dev/null || echo 0)
  printf "Universal patterns: %s    Anti-patterns: %s\n" "$up_count" "$ap_count"
}

# ============================================================================
# Section 6 — Drift detector
# ============================================================================
render_drift() {
  print_section_header "DRIFT"

  local states; states="$(discover_projects)"
  if [[ -z "$states" ]]; then
    printf "${YELLOW}(no projects discovered)${NC}\n"
    return 0
  fi

  printf "%-30s %-30s %-30s %s\n" "Project" "STATE phase" "Newest dir" "Status"
  printf "%-30s %-30s %-30s %s\n" "-------" "-----------" "----------" "------"

  local now; now=$(date +%s)
  local total=0 drifted=0
  local s proj phase newest_dir newest_phase status color s_mtime age
  while IFS= read -r s; do
    [[ -z "$s" ]] && continue
    total=$(( total + 1 ))
    proj="$(basename "$(dirname "$(dirname "$s")")")"
    phase="$(parse_current_phase "$s" 2>/dev/null)"
    [[ -z "$phase" ]] && phase="(unknown)"

    # Newest phase dir
    local phases_dir; phases_dir="$(dirname "$s")/phases"
    if [[ -d "$phases_dir" ]]; then
      newest_dir="$(ls -td "$phases_dir"/*/ 2>/dev/null | head -1)"
      newest_dir="$(basename "${newest_dir%/}")"
    else
      newest_dir="(no phases/)"
    fi
    [[ -z "$newest_dir" ]] && newest_dir="(empty)"

    # Drift heuristic: if phase text contains the directory's phase number,
    # MATCH. Else DRIFT (subject to 60s tolerance window).
    s_mtime="$(file_mtime "$s")"
    age=$(( now - s_mtime ))

    # Extract leading number from newest_dir (e.g. "06-cross..." -> "06")
    local dir_num; dir_num="$(echo "$newest_dir" | awk -F- '{print $1}')"

    if [[ -n "$dir_num" ]] && echo "$phase" | grep -qE "$dir_num|Phase $dir_num"; then
      color="$GREEN"; status="✅ MATCH"
    elif [[ "$age" -lt 60 ]]; then
      color="$BLUE"; status="ℹ INFO (active)"
    else
      color="$RED"; status="✗ DRIFT"
      drifted=$(( drifted + 1 ))
    fi

    printf "%-30s %-30s %-30s ${color}%s${NC}\n" \
      "$proj" "${phase:0:30}" "${newest_dir:0:30}" "$status"
  done <<< "$states"

  echo ""
  if [[ "$drifted" -gt 0 ]]; then
    printf "${RED}Drift: %s/%s projects${NC}\n" "$drifted" "$total"
  else
    printf "${GREEN}Drift: 0/%s projects${NC}\n" "$total"
  fi
}

# ============================================================================
# Section 7 — Tier health
# ============================================================================
render_tier_health() {
  print_section_header "TIER HEALTH"

  if [[ ! -d "$VERIFY_REPORTS_DIR" ]]; then
    printf "${YELLOW}(no verification-reports dir — run 'ark verify')${NC}\n"
    return 0
  fi

  local latest
  latest=$(ls -t "$VERIFY_REPORTS_DIR"/*.md 2>/dev/null | head -1)
  if [[ -z "$latest" ]]; then
    printf "${YELLOW}(no verification reports yet — run 'ark verify')${NC}\n"
    return 0
  fi

  # Parse pass/fail/skip per tier from the "## Detailed Results" lines.
  # Format example: "- ✅ T7: name" / "- ❌ T12: name" / "- ⏭  T1: name (skipped)"
  printf "%-8s %6s %6s %6s %s\n" "Tier" "Pass" "Fail" "Skip" "Status"
  printf "%-8s %6s %6s %6s %s\n" "----" "----" "----" "----" "------"

  awk '
    /T[0-9]+:/ {
      # Find the T<num> token
      for (i=1; i<=NF; i++) {
        if (match($i, /^T[0-9]+:/)) {
          tier = substr($i, 2)
          sub(/:$/, "", tier)
          if ($0 ~ /✅/)      pass[tier]++
          else if ($0 ~ /❌/) fail[tier]++
          else if ($0 ~ /⏭/) skip[tier]++
          else if ($0 ~ /⚠/) warn[tier]++
          break
        }
      }
    }
    END {
      # Sort numerically
      n = 0
      for (t in pass) tiers[n++] = t
      for (t in fail) if (!(t in pass)) tiers[n++] = t
      for (t in skip) if (!(t in pass) && !(t in fail)) tiers[n++] = t
      # Bubble sort by numeric value
      for (i=0; i<n; i++) for (j=i+1; j<n; j++) {
        if (int(tiers[i]) > int(tiers[j])) { tmp=tiers[i]; tiers[i]=tiers[j]; tiers[j]=tmp }
      }
      for (i=0; i<n; i++) {
        t = tiers[i]
        p = pass[t]+0; f = fail[t]+0; s = skip[t]+0
        if (f > 0)      mark = "❌"
        else if (p > 0) mark = "✅"
        else            mark = "⏭ "
        printf "T%-7s %6d %6d %6d %s\n", t, p, f, s, mark
      }
    }
  ' "$latest"

  echo ""
  printf "Report: %s\n" "$(basename "$latest")"
}

# ============================================================================
# Main
# ============================================================================
main() {
  local started; started=$(date +%s)
  # Use python for ms precision (Bash 3 has no $EPOCHREALTIME)
  local started_ms; started_ms=$(python3 -c 'import time; print(int(time.time()*1000))' 2>/dev/null || echo 0)

  render_portfolio_grid
  render_escalations
  render_budget
  render_recent_decisions
  render_learning_watch
  render_drift
  render_tier_health

  local elapsed=$(( $(date +%s) - started ))
  local elapsed_ms=0
  if [[ "$started_ms" -gt 0 ]]; then
    local now_ms; now_ms=$(python3 -c 'import time; print(int(time.time()*1000))' 2>/dev/null || echo 0)
    elapsed_ms=$(( now_ms - started_ms ))
  fi

  echo ""
  printf "${BLUE}━━━${NC} Rendered in %dms (%ds) · vault: %s\n" \
    "$elapsed_ms" "$elapsed" "$VAULT_PATH"
}

main "$@"
