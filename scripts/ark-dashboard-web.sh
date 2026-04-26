#!/usr/bin/env bash
# ark-dashboard-web.sh — Tier C local web dashboard for AOS Phase 6.5
#
# Read-only over the same data sources as Tier A (ark-dashboard.sh).
# Renders an HTML page (single index.html) into a tmpdir and serves it via
# python3 -m http.server. Browser auto-refreshes via <meta http-equiv="refresh">.
#
# Usage:
#   bash scripts/ark-dashboard-web.sh
#   ARK_DASHBOARD_PORT=7920 bash scripts/ark-dashboard-web.sh
#
# Constraints (locked):
#   - Bash 3 compat (macOS default).
#   - READ-ONLY: every sqlite3 call uses -readonly.
#   - No external HTTP libs; only python3 stdlib http.server.
#   - tmpdir + background regen loop cleaned up on EXIT (trap).
#   - No `read -p` prompts. (`read -r` for stream/pipe parsing is AOS: intentional.)
#   - HTML-escape all data values (defense vs. injection from project names,
#     lesson titles, etc.). Local-only, but discipline matters.
#
# Phase 6.5 — REQ-DASH-09, REQ-DASH-10.

set -uo pipefail

# ============================================================================
# Data-source resolution (mirror ark-dashboard.sh)
# ============================================================================
VAULT_PATH="${ARK_HOME:-$HOME/vaults/ark}"
POLICY_DB="${ARK_POLICY_DB:-$VAULT_PATH/observability/policy.db}"
PORTFOLIO_ROOT="${ARK_PORTFOLIO_ROOT:-$HOME/code}"
ESCALATIONS_FILE="$VAULT_PATH/ESCALATIONS.md"
VERIFY_REPORTS_DIR="$VAULT_PATH/observability/verification-reports"
UNIVERSAL_PATTERNS="$VAULT_PATH/lessons/universal-patterns.md"
ANTI_PATTERNS="$VAULT_PATH/bootstrap/anti-patterns.md"
POLICY_EVOLUTION="$VAULT_PATH/observability/policy-evolution.md"

WEB_PORT="${ARK_DASHBOARD_PORT:-7919}"
WEB_DIR="$(mktemp -d -t ark-dashboard-web)"
REGEN_PID=""
HTTP_PID=""

# ============================================================================
# Cleanup trap
#
# CRITICAL: do NOT `exec python3` — that replaces this bash, drops the trap,
# and orphans the regen loop. Instead, run python as a child and forward
# signals to it from the trap. EXIT runs unconditionally (normal exit, INT,
# TERM, or hook chained via the explicit signal traps below).
# ============================================================================
cleanup() {
  local rc=$?
  trap - EXIT INT TERM   # idempotent — prevent re-entry
  if [[ -n "$HTTP_PID" ]]; then
    kill "$HTTP_PID" 2>/dev/null || true
    wait "$HTTP_PID" 2>/dev/null || true
  fi
  if [[ -n "$REGEN_PID" ]]; then
    kill "$REGEN_PID" 2>/dev/null || true
    wait "$REGEN_PID" 2>/dev/null || true
  fi
  if [[ -n "${WEB_DIR:-}" && -d "$WEB_DIR" ]]; then
    rm -rf "$WEB_DIR"
  fi
  exit $rc
}
trap cleanup EXIT
trap 'cleanup' INT TERM

# ============================================================================
# Helpers
# ============================================================================

# HTML-escape stdin → stdout. Order matters: & first, then < >.
html_escape() {
  sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'
}

# db_query <sql> — wraps sqlite3 -readonly with graceful degradation.
db_query() {
  local sql="$1"
  if [[ ! -f "$POLICY_DB" ]]; then
    return 0
  fi
  sqlite3 -readonly -separator '|' "$POLICY_DB" "$sql" 2>/dev/null || true
}

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

file_mtime() {
  stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0
}

discover_projects() {
  if [[ ! -d "$PORTFOLIO_ROOT" ]]; then return 0; fi
  find "$PORTFOLIO_ROOT" -maxdepth 3 -type f -name STATE.md \
       -path '*/.planning/STATE.md' 2>/dev/null
}

parse_current_phase() {
  awk '/^current_phase:/ { sub(/^current_phase: */, ""); gsub(/"/, ""); print; exit }' "$1"
}

# ============================================================================
# HTML section renderers
# ============================================================================

render_html_head() {
  cat <<'HTML_HEAD'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="refresh" content="5">
<title>Ark Dashboard</title>
<style>
:root {
  --bg: #fafafa;
  --fg: #1a1a1a;
  --muted: #666;
  --accent: #2266cc;
  --border: #ddd;
  --row-alt: #f0f0f0;
  --green: #1a7f37;
  --yellow: #9a6700;
  --red: #cf222e;
  --blue: #0969da;
  --bar-bg: #e6e6e6;
  --bar-fill: #2266cc;
  --bar-warn: #d4a72c;
  --bar-crit: #cf222e;
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #0d1117;
    --fg: #e6edf3;
    --muted: #8b949e;
    --accent: #58a6ff;
    --border: #30363d;
    --row-alt: #161b22;
    --green: #3fb950;
    --yellow: #d29922;
    --red: #f85149;
    --blue: #58a6ff;
    --bar-bg: #21262d;
    --bar-fill: #58a6ff;
    --bar-warn: #d29922;
    --bar-crit: #f85149;
  }
}
* { box-sizing: border-box; }
body {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
  background: var(--bg);
  color: var(--fg);
  margin: 0;
  padding: 1.5rem;
  font-size: 14px;
  line-height: 1.5;
}
header {
  border-bottom: 2px solid var(--accent);
  margin-bottom: 1rem;
  padding-bottom: 0.5rem;
}
header h1 { margin: 0; font-size: 1.5rem; }
header .sub { color: var(--muted); font-size: 0.9rem; }
details {
  margin: 1rem 0;
  padding: 0.5rem 1rem;
  border: 1px solid var(--border);
  border-radius: 6px;
  background: var(--bg);
}
details > summary {
  cursor: pointer;
  font-weight: 600;
  font-size: 1.1rem;
  padding: 0.25rem 0;
  color: var(--accent);
}
table {
  border-collapse: collapse;
  width: 100%;
  margin: 0.5rem 0;
  font-size: 0.9rem;
}
th, td {
  padding: 0.4rem 0.6rem;
  text-align: left;
  border-bottom: 1px solid var(--border);
}
th {
  background: var(--row-alt);
  font-weight: 600;
}
tr:nth-child(even) td { background: var(--row-alt); }
.green { color: var(--green); font-weight: 600; }
.yellow { color: var(--yellow); font-weight: 600; }
.red { color: var(--red); font-weight: 600; }
.blue { color: var(--blue); font-weight: 600; }
.muted { color: var(--muted); font-style: italic; }
.bar-wrap {
  display: inline-block;
  width: 140px;
  height: 12px;
  background: var(--bar-bg);
  border-radius: 3px;
  overflow: hidden;
  vertical-align: middle;
}
.bar-fill {
  height: 100%;
  background: var(--bar-fill);
  transition: width 0.3s;
}
.bar-warn { background: var(--bar-warn); }
.bar-crit { background: var(--bar-crit); }
footer {
  margin-top: 2rem;
  padding-top: 1rem;
  border-top: 1px solid var(--border);
  color: var(--muted);
  font-size: 0.85rem;
}
code { font-family: "SF Mono", Monaco, "Cascadia Code", monospace; font-size: 0.85em; }
@media (max-width: 600px) {
  body { padding: 0.75rem; font-size: 13px; }
  table { font-size: 0.8rem; }
  th, td { padding: 0.3rem 0.4rem; }
}
</style>
</head>
<body>
<header>
  <h1>🚢 Ark Dashboard</h1>
  <div class="sub">Tier C · auto-refresh every 5s · read-only</div>
</header>
HTML_HEAD
}

render_html_section_portfolio() {
  echo '<details open><summary>1. Portfolio</summary>'
  local states; states="$(discover_projects)"
  if [[ -z "$states" ]]; then
    printf '<p class="muted">(no projects discovered under %s)</p></details>\n' \
      "$(printf '%s' "$PORTFOLIO_ROOT" | html_escape)"
    return 0
  fi
  echo '<table><thead><tr><th>Project</th><th>Phase</th><th>Last activity</th><th>Health</th></tr></thead><tbody>'
  local now; now=$(date +%s)
  local s phase mtime ago cls status proj
  while IFS= read -r s; do  # AOS: intentional
    [[ -z "$s" ]] && continue
    proj="$(basename "$(dirname "$(dirname "$s")")")"
    phase="$(parse_current_phase "$s" 2>/dev/null)"
    [[ -z "$phase" ]] && phase="(unknown)"
    mtime="$(file_mtime "$s")"
    ago="$(human_ago "$mtime")"
    local diff=$(( now - mtime ))
    if   [[ "$diff" -lt 86400 ]];  then cls="green";  status="✅ active"
    elif [[ "$diff" -lt 604800 ]]; then cls="yellow"; status="⚠ stale"
    else                                cls="red";    status="✗ cold"
    fi
    printf '<tr><td><code>%s</code></td><td>%s</td><td>%s</td><td class="%s">%s</td></tr>\n' \
      "$(printf '%s' "$proj"  | html_escape)" \
      "$(printf '%s' "$phase" | html_escape)" \
      "$(printf '%s' "$ago"   | html_escape)" \
      "$cls" \
      "$(printf '%s' "$status" | html_escape)"
  done <<< "$states"
  echo '</tbody></table></details>'
}

render_html_section_escalations() {
  echo '<details open><summary>2. Escalations</summary>'
  if [[ ! -f "$ESCALATIONS_FILE" ]]; then
    echo '<p class="green">✅ No escalations queue file (no blockers)</p></details>'
    return 0
  fi
  local pending resolved
  pending=$(grep -c '^## \[PENDING\]' "$ESCALATIONS_FILE" 2>/dev/null || echo 0)
  resolved=$(grep -c '^## \[RESOLVED\]' "$ESCALATIONS_FILE" 2>/dev/null || echo 0)
  if [[ "$pending" -eq 0 ]]; then
    printf '<p class="green">✅ 0 pending blockers (resolved: %s)</p></details>\n' \
      "$(printf '%s' "$resolved" | html_escape)"
    return 0
  fi
  printf '<p class="red">🚨 %s pending blockers (resolved: %s)</p>\n' \
    "$(printf '%s' "$pending" | html_escape)" \
    "$(printf '%s' "$resolved" | html_escape)"
  echo '<table><thead><tr><th>Class</th><th>Count</th></tr></thead><tbody>'
  local cls c
  for cls in budget architectural destructive repeated_failure; do
    c=$(awk -v cls="$cls" '
      /^## \[PENDING\]/ { in_p=1; matched=0 }
      /^## \[RESOLVED\]/ { in_p=0 }
      in_p && tolower($0) ~ cls && !matched { matched=1; n++ }
      END { print n+0 }
    ' "$ESCALATIONS_FILE" 2>/dev/null || echo 0)
    printf '<tr><td><code>%s</code></td><td>%s</td></tr>\n' \
      "$(printf '%s' "$cls" | html_escape)" \
      "$(printf '%s' "$c" | html_escape)"
  done
  echo '</tbody></table>'
  echo '<p>Recent pending IDs:</p><ul>'
  awk '/^## \[PENDING\]/ { print }' "$ESCALATIONS_FILE" 2>/dev/null | head -10 | \
    while IFS= read -r line; do  # AOS: intentional
      printf '<li><code>%s</code></li>\n' "$(printf '%s' "$line" | html_escape)"
    done
  echo '</ul></details>'
}

render_html_section_budget() {
  echo '<details open><summary>3. Budget</summary>'
  local states; states="$(discover_projects)"
  if [[ -z "$states" ]]; then
    echo '<p class="muted">(no projects discovered)</p></details>'
    return 0
  fi
  local found=0 total_used=0 total_cap=0
  local rows_html=""
  local s budget_file proj used cap headroom_pct cls status pct_used bar_cls
  while IFS= read -r s; do  # AOS: intentional
    [[ -z "$s" ]] && continue
    proj="$(basename "$(dirname "$(dirname "$s")")")"
    budget_file="$(dirname "$s")/budget.json"
    [[ ! -f "$budget_file" ]] && continue
    found=1
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
      headroom_pct=100; pct_used=0
    else
      headroom_pct=$(( (cap - used) * 100 / cap ))
      [[ "$headroom_pct" -lt 0 ]] && headroom_pct=0
      pct_used=$(( used * 100 / cap ))
      [[ "$pct_used" -gt 100 ]] && pct_used=100
    fi
    if   [[ "$headroom_pct" -lt 10 ]]; then cls="red";    status="✗ CAP";   bar_cls="bar-crit"
    elif [[ "$headroom_pct" -lt 30 ]]; then cls="yellow"; status="⚠ tight"; bar_cls="bar-warn"
    else                                    cls="green";  status="✅ ok";    bar_cls=""
    fi
    total_used=$(( total_used + used ))
    total_cap=$(( total_cap + cap ))
    rows_html+=$(printf '<tr><td><code>%s</code></td><td>%d</td><td>%d</td><td><div class="bar-wrap"><div class="bar-fill %s" style="width:%d%%"></div></div> %d%%</td><td class="%s">%s</td></tr>\n' \
      "$(printf '%s' "$proj" | html_escape)" \
      "$used" "$cap" "$bar_cls" "$pct_used" "$headroom_pct" "$cls" \
      "$(printf '%s' "$status" | html_escape)")
  done <<< "$states"
  if [[ "$found" -eq 0 ]]; then
    echo '<p class="muted">(no budget.json files found)</p></details>'
    return 0
  fi
  echo '<table><thead><tr><th>Project</th><th>Used</th><th>Cap</th><th>Headroom</th><th>Risk</th></tr></thead><tbody>'
  printf '%s' "$rows_html"
  local agg_pct=100
  if [[ "$total_cap" -gt 0 ]]; then
    agg_pct=$(( (total_cap - total_used) * 100 / total_cap ))
  fi
  printf '<tr><td><strong>TOTAL</strong></td><td><strong>%d</strong></td><td><strong>%d</strong></td><td><strong>%d%%</strong></td><td></td></tr>\n' \
    "$total_used" "$total_cap" "$agg_pct"
  echo '</tbody></table></details>'
}

render_html_section_recent_decisions() {
  echo '<details open><summary>4. Recent Decisions</summary>'
  if [[ ! -f "$POLICY_DB" ]]; then
    printf '<p class="muted">(policy.db missing — %s)</p></details>\n' \
      "$(printf '%s' "$POLICY_DB" | html_escape)"
    return 0
  fi
  local total
  total=$(db_query "SELECT COUNT(*) FROM decisions;")
  if [[ -z "$total" ]] || [[ "$total" -eq 0 ]]; then
    echo '<p class="muted">(policy.db empty — no decisions yet)</p></details>'
    return 0
  fi
  printf '<p>Total rows: <strong>%s</strong> &nbsp;(showing last 50)</p>\n' \
    "$(printf '%s' "$total" | html_escape)"
  echo '<table><thead><tr><th>Timestamp (UTC)</th><th>Class</th><th>Decision</th><th>Reason</th></tr></thead><tbody>'
  local rows
  rows=$(db_query "SELECT ts, class, decision, substr(reason, 1, 60) FROM decisions ORDER BY ts DESC LIMIT 50;")
  local IFS_old="$IFS"
  IFS=$'\n'
  local row ts class decision reason cls
  for row in $rows; do
    [[ -z "$row" ]] && continue
    IFS='|' read -r ts class decision reason <<< "$row"  # AOS: intentional (stream read, not prompt)
    case "$class" in
      escalation)                       cls="red" ;;
      self_improve|lesson_promote)      cls="blue" ;;
      dispatch_failure)                 cls="yellow" ;;
      *)                                cls="" ;;
    esac
    if [[ -n "$cls" ]]; then
      printf '<tr><td><code>%s</code></td><td class="%s">%s</td><td>%s</td><td>%s</td></tr>\n' \
        "$(printf '%s' "${ts:0:19}" | html_escape)" \
        "$cls" \
        "$(printf '%s' "$class"    | html_escape)" \
        "$(printf '%s' "$decision" | html_escape)" \
        "$(printf '%s' "$reason"   | html_escape)"
    else
      printf '<tr><td><code>%s</code></td><td>%s</td><td>%s</td><td>%s</td></tr>\n' \
        "$(printf '%s' "${ts:0:19}" | html_escape)" \
        "$(printf '%s' "$class"    | html_escape)" \
        "$(printf '%s' "$decision" | html_escape)" \
        "$(printf '%s' "$reason"   | html_escape)"
    fi
  done
  IFS="$IFS_old"
  echo '</tbody></table>'
  echo '<p>Class breakdown (last 50):</p>'
  echo '<table><thead><tr><th>Class</th><th>Count</th></tr></thead><tbody>'
  local class_counts
  class_counts=$(db_query "
    SELECT class, COUNT(*) FROM (
      SELECT class FROM decisions ORDER BY ts DESC LIMIT 50
    ) GROUP BY class ORDER BY COUNT(*) DESC;
  ")
  IFS=$'\n'
  local cls_row c_class c_n
  for cls_row in $class_counts; do
    [[ -z "$cls_row" ]] && continue
    IFS='|' read -r c_class c_n <<< "$cls_row"  # AOS: intentional (stream read, not prompt)
    printf '<tr><td><code>%s</code></td><td>%s</td></tr>\n' \
      "$(printf '%s' "$c_class" | html_escape)" \
      "$(printf '%s' "$c_n" | html_escape)"
  done
  IFS="$IFS_old"
  echo '</tbody></table></details>'
}

render_html_section_learning() {
  echo '<details open><summary>5. Learning Watch</summary>'
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
      echo '<p class="muted">(no promotions in last 7 days)</p>'
    else
      echo '<p>Recent promotions (last 7 days):</p>'
      echo '<table><thead><tr><th>Timestamp</th><th>Decision</th><th>Reason</th></tr></thead><tbody>'
      local IFS_old="$IFS"
      IFS=$'\n'
      local row ts dec rsn
      for row in $promotions; do
        [[ -z "$row" ]] && continue
        IFS='|' read -r ts dec rsn <<< "$row"  # AOS: intentional (stream read, not prompt)
        printf '<tr><td><code>%s</code></td><td>%s</td><td>%s</td></tr>\n' \
          "$(printf '%s' "${ts:0:19}" | html_escape)" \
          "$(printf '%s' "$dec" | html_escape)" \
          "$(printf '%s' "$rsn" | html_escape)"
      done
      IFS="$IFS_old"
      echo '</tbody></table>'
    fi
  else
    echo '<p class="muted">(policy.db missing)</p>'
  fi

  if [[ -f "$POLICY_EVOLUTION" ]]; then
    local mediocre_count
    mediocre_count=$(awk '
      /^## Mediocre/ { in_m=1; next }
      /^## / && in_m { in_m=0 }
      in_m && /^\| [a-z]/ { n++ }
      END { print n+0 }
    ' "$POLICY_EVOLUTION" 2>/dev/null)
    printf '<p>Patterns near promotion threshold: <strong>%s</strong></p>\n' \
      "$(printf '%s' "${mediocre_count:-0}" | html_escape)"
  else
    echo '<p class="muted">(policy-evolution.md missing)</p>'
  fi

  local up_count ap_count
  up_count=$(grep -c '^## ' "$UNIVERSAL_PATTERNS" 2>/dev/null || echo 0)
  ap_count=$(grep -c '^## ' "$ANTI_PATTERNS" 2>/dev/null || echo 0)
  printf '<p>Universal patterns: <strong>%s</strong> &nbsp; Anti-patterns: <strong>%s</strong></p>\n' \
    "$(printf '%s' "$up_count" | html_escape)" \
    "$(printf '%s' "$ap_count" | html_escape)"
  echo '</details>'
}

render_html_section_drift() {
  echo '<details open><summary>6. Drift Detector</summary>'
  local states; states="$(discover_projects)"
  if [[ -z "$states" ]]; then
    echo '<p class="muted">(no projects discovered)</p></details>'
    return 0
  fi
  echo '<table><thead><tr><th>Project</th><th>STATE phase</th><th>Newest dir</th><th>Status</th></tr></thead><tbody>'
  local now; now=$(date +%s)
  local total=0 drifted=0
  local s proj phase newest_dir cls status s_mtime age phases_dir dir_num
  while IFS= read -r s; do  # AOS: intentional
    [[ -z "$s" ]] && continue
    total=$(( total + 1 ))
    proj="$(basename "$(dirname "$(dirname "$s")")")"
    phase="$(parse_current_phase "$s" 2>/dev/null)"
    [[ -z "$phase" ]] && phase="(unknown)"
    phases_dir="$(dirname "$s")/phases"
    if [[ -d "$phases_dir" ]]; then
      newest_dir="$(ls -td "$phases_dir"/*/ 2>/dev/null | head -1)"
      newest_dir="$(basename "${newest_dir%/}")"
    else
      newest_dir="(no phases/)"
    fi
    [[ -z "$newest_dir" ]] && newest_dir="(empty)"
    s_mtime="$(file_mtime "$s")"
    age=$(( now - s_mtime ))
    dir_num="$(echo "$newest_dir" | awk -F- '{print $1}')"
    if [[ -n "$dir_num" ]] && echo "$phase" | grep -qE "$dir_num|Phase $dir_num"; then
      cls="green"; status="✅ MATCH"
    elif [[ "$age" -lt 60 ]]; then
      cls="blue"; status="ℹ INFO (active)"
    else
      cls="red"; status="✗ DRIFT"
      drifted=$(( drifted + 1 ))
    fi
    printf '<tr><td><code>%s</code></td><td>%s</td><td><code>%s</code></td><td class="%s">%s</td></tr>\n' \
      "$(printf '%s' "$proj"        | html_escape)" \
      "$(printf '%s' "$phase"       | html_escape)" \
      "$(printf '%s' "$newest_dir"  | html_escape)" \
      "$cls" \
      "$(printf '%s' "$status"      | html_escape)"
  done <<< "$states"
  echo '</tbody></table>'
  if [[ "$drifted" -gt 0 ]]; then
    printf '<p class="red">Drift: %s/%s projects</p>\n' \
      "$(printf '%s' "$drifted" | html_escape)" \
      "$(printf '%s' "$total"   | html_escape)"
  else
    printf '<p class="green">Drift: 0/%s projects</p>\n' \
      "$(printf '%s' "$total" | html_escape)"
  fi
  echo '</details>'
}

render_html_section_tier_health() {
  echo '<details open><summary>7. Tier Health</summary>'
  if [[ ! -d "$VERIFY_REPORTS_DIR" ]]; then
    echo '<p class="muted">(no verification-reports dir — run <code>ark verify</code>)</p></details>'
    return 0
  fi
  local latest
  latest=$(ls -t "$VERIFY_REPORTS_DIR"/*.md 2>/dev/null | head -1)
  if [[ -z "$latest" ]]; then
    echo '<p class="muted">(no verification reports yet — run <code>ark verify</code>)</p></details>'
    return 0
  fi
  echo '<table><thead><tr><th>Tier</th><th>Pass</th><th>Fail</th><th>Skip</th><th>Status</th></tr></thead><tbody>'
  awk '
    /T[0-9]+:/ {
      for (i=1; i<=NF; i++) {
        if (match($i, /^T[0-9]+:/)) {
          tier = substr($i, 2); sub(/:$/, "", tier)
          if ($0 ~ /✅/)      pass[tier]++
          else if ($0 ~ /❌/) fail[tier]++
          else if ($0 ~ /⏭/) skip[tier]++
          else if ($0 ~ /⚠/) warn[tier]++
          break
        }
      }
    }
    END {
      n = 0
      for (t in pass) tiers[n++] = t
      for (t in fail) if (!(t in pass)) tiers[n++] = t
      for (t in skip) if (!(t in pass) && !(t in fail)) tiers[n++] = t
      for (i=0; i<n; i++) for (j=i+1; j<n; j++) {
        if (int(tiers[i]) > int(tiers[j])) { tmp=tiers[i]; tiers[i]=tiers[j]; tiers[j]=tmp }
      }
      for (i=0; i<n; i++) {
        t = tiers[i]
        p = pass[t]+0; f = fail[t]+0; s = skip[t]+0
        if (f > 0)      { mark = "❌"; cls = "red" }
        else if (p > 0) { mark = "✅"; cls = "green" }
        else            { mark = "⏭";  cls = "muted" }
        printf "<tr><td><code>T%s</code></td><td>%d</td><td>%d</td><td>%d</td><td class=\"%s\">%s</td></tr>\n", \
          t, p, f, s, cls, mark
      }
    }
  ' "$latest"
  echo '</tbody></table>'
  printf '<p>Report: <code>%s</code></p>\n' \
    "$(basename "$latest" | html_escape)"
  echo '</details>'
}

render_html_footer() {
  local rendered_at vault_real
  rendered_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  vault_real="$(cd "$VAULT_PATH" 2>/dev/null && pwd -P || printf '%s' "$VAULT_PATH")"
  printf '<footer>Rendered: <code>%s</code> · Vault: <code>%s</code></footer>\n</body></html>\n' \
    "$(printf '%s' "$rendered_at" | html_escape)" \
    "$(printf '%s' "$vault_real"  | html_escape)"
}

# ============================================================================
# regen_html — atomic write to $WEB_DIR/index.html
# ============================================================================
regen_html() {
  local tmp_out="$WEB_DIR/.index.html.tmp"
  {
    render_html_head
    render_html_section_portfolio
    render_html_section_escalations
    render_html_section_budget
    render_html_section_recent_decisions
    render_html_section_learning
    render_html_section_drift
    render_html_section_tier_health
    render_html_footer
  } > "$tmp_out" 2>/dev/null
  mv "$tmp_out" "$WEB_DIR/index.html"
}

# ============================================================================
# Main
# ============================================================================
main() {
  # Initial render before serving (so first GET returns content immediately).
  regen_html

  # Background regen loop — every 5s.
  ( while true; do sleep 5; regen_html; done ) &
  REGEN_PID=$!

  printf '🌐 Ark Dashboard available at http://localhost:%s  (Ctrl-C to stop)\n' "$WEB_PORT"
  printf '   Webroot: %s\n' "$WEB_DIR"
  printf '   Refresh: 5s (browser <meta refresh>)\n\n'

  # Foreground (blocking): run python as a child so this bash retains the
  # cleanup trap. Bash 3 `wait <pid>` is NOT interruptible by signals — so
  # we loop on a non-blocking probe. INT/TERM hits this bash, the trap fires
  # (sets STOP=1), we exit the loop, cleanup runs (kills children, rm tmpdir).
  python3 -m http.server "$WEB_PORT" --directory "$WEB_DIR" &
  HTTP_PID=$!
  STOP=0
  trap 'STOP=1' INT TERM
  while [[ "$STOP" -eq 0 ]]; do
    # Poll: has python died on its own? (e.g. port already in use, broken pipe)
    if ! kill -0 "$HTTP_PID" 2>/dev/null; then
      break
    fi
    sleep 1
  done
}

main "$@"
