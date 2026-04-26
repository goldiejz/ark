#!/usr/bin/env bash
# ark-policy.sh — Autonomous Operating System decision module
#
# All routine resource decisions route through here. Scripts call policy_*
# functions; the module decides without prompting the user. Decisions are
# audit-logged to observability/policy-decisions.jsonl.
#
# Escalation (user IS prompted) ONLY for these 4 classes:
#   1. Monthly budget exceeded (real cost ceiling)
#   2. Architectural ambiguity (multiple valid approaches, no policy preference)
#   3. Destructive ops (force-push, drop data, prod deploy)
#   4. Repeated self-heal failure (>=3 retries on same task)
#
# Every other "what should I do?" question is answered here, autonomously.

VAULT_PATH="${ARK_HOME:-$HOME/vaults/ark}"
POLICY_LOG="$VAULT_PATH/observability/policy-decisions.jsonl"
mkdir -p "$(dirname "$POLICY_LOG")" 2>/dev/null

# Thresholds (overridable by env)
ARK_MONTHLY_ESCALATE_PCT="${ARK_MONTHLY_ESCALATE_PCT:-95}"  # escalate above this monthly use %
ARK_SELF_HEAL_MAX="${ARK_SELF_HEAL_MAX:-3}"                  # max self-heal retries before escalate

# === Audit helper ===
_policy_log() {
  local class="$1"
  local decision="$2"
  local reason="$3"
  local context="${4:-}"
  local ts
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  printf '{"ts":"%s","class":"%s","decision":"%s","reason":"%s","context":%s}\n' \
    "$ts" "$class" "$decision" "$reason" "${context:-null}" >> "$POLICY_LOG"
}

# === Budget decision ===
# Args: phase_used phase_cap monthly_used monthly_cap
# Emits to stdout: AUTO_RESET | PROCEED | ESCALATE_MONTHLY_CAP
policy_budget_decision() {
  local phase_used="${1:-0}"
  local phase_cap="${2:-50000}"
  local monthly_used="${3:-0}"
  local monthly_cap="${4:-1000000}"

  # Monthly use percentage (integer math)
  local monthly_pct=0
  if [[ "$monthly_cap" -gt 0 ]]; then
    monthly_pct=$(( monthly_used * 100 / monthly_cap ))
  fi

  # Real cost ceiling — escalate
  if [[ "$monthly_pct" -ge "$ARK_MONTHLY_ESCALATE_PCT" ]]; then
    _policy_log "budget" "ESCALATE_MONTHLY_CAP" \
      "monthly_use_${monthly_pct}pct_>=_${ARK_MONTHLY_ESCALATE_PCT}pct" \
      "{\"phase_used\":$phase_used,\"phase_cap\":$phase_cap,\"monthly_used\":$monthly_used,\"monthly_cap\":$monthly_cap}"
    echo "ESCALATE_MONTHLY_CAP"
    return 2
  fi

  # Phase cap exceeded but monthly headroom — auto-reset phase counter
  if [[ "$phase_used" -ge "$phase_cap" ]]; then
    _policy_log "budget" "AUTO_RESET" \
      "phase_cap_hit_monthly_headroom_${monthly_pct}pct" \
      "{\"phase_used\":$phase_used,\"phase_cap\":$phase_cap,\"monthly_used\":$monthly_used,\"monthly_cap\":$monthly_cap}"
    echo "AUTO_RESET"
    return 0
  fi

  echo "PROCEED"
  return 0
}

# === Dispatcher routing ===
# Args: task_complexity (lean|standard|strong|deep) [budget_tier]
# Honors env stubs: ARK_FORCE_QUOTA_CODEX, ARK_FORCE_QUOTA_GEMINI (used in tests)
# Emits: codex | gemini | haiku-api | claude-session | regex-fallback
policy_dispatcher_route() {
  local complexity="${1:-standard}"
  local tier="${2:-GREEN}"

  # Detect runtime context (active session > codex > gemini)
  local primary
  if [[ -x "$VAULT_PATH/scripts/ark-context.sh" ]]; then
    primary=$(bash "$VAULT_PATH/scripts/ark-context.sh" --primary 2>/dev/null || echo "regex-fallback")
  else
    primary="regex-fallback"
  fi

  # Active Claude session ALWAYS wins — it's the most reliable dispatcher
  if [[ "$primary" == "claude-code-session" ]]; then
    _policy_log "dispatch" "claude-session" "active_session_detected" \
      "{\"complexity\":\"$complexity\",\"tier\":\"$tier\"}"
    echo "claude-session"
    return 0
  fi

  # External CLI availability — honor force-quota stubs for tests
  local codex_available=false
  local gemini_available=false
  if [[ "${ARK_FORCE_QUOTA_CODEX:-false}" != "true" ]] && command -v codex >/dev/null 2>&1; then
    codex_available=true
  fi
  if [[ "${ARK_FORCE_QUOTA_GEMINI:-false}" != "true" ]] && command -v gemini >/dev/null 2>&1; then
    gemini_available=true
  fi

  # RED tier — no paid dispatch
  if [[ "$tier" == "RED" || "$tier" == "BLACK" ]]; then
    _policy_log "dispatch" "regex-fallback" "tier_${tier}_no_paid_dispatch" \
      "{\"complexity\":\"$complexity\",\"tier\":\"$tier\"}"
    echo "regex-fallback"
    return 0
  fi

  # Route by complexity preference, fall through to any available
  case "$complexity" in
    lean|standard)
      if $codex_available; then echo "codex"; _policy_log "dispatch" "codex" "preferred_for_$complexity" "null"; return 0; fi
      if $gemini_available; then echo "gemini"; _policy_log "dispatch" "gemini" "codex_unavailable" "null"; return 0; fi
      ;;
    strong|deep)
      if $gemini_available; then echo "gemini"; _policy_log "dispatch" "gemini" "preferred_for_$complexity" "null"; return 0; fi
      if $codex_available; then echo "codex"; _policy_log "dispatch" "codex" "gemini_unavailable" "null"; return 0; fi
      ;;
  esac

  # API fallback if key present
  if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
    _policy_log "dispatch" "haiku-api" "all_clis_unavailable_api_key_present" "null"
    echo "haiku-api"
    return 0
  fi

  # Last resort — regex fallback (no dispatch, cached patterns only)
  _policy_log "dispatch" "regex-fallback" "no_dispatcher_available" "null"
  echo "regex-fallback"
  return 0
}

# === Zero-task phase decision ===
# Args: phase_dir plan_count
# Emits: SKIP_LOGGED | ESCALATE_AMBIGUOUS
policy_zero_tasks() {
  local phase_dir="$1"
  local plan_count="${2:-0}"

  # If no plans at all, may be intentional (e.g., bootstrap-only phase) — skip
  # If plans exist but all are checked off, also skip (legitimately complete)
  # Only escalate if user roadmap is fully zero across ALL phases (true ambiguity)
  _policy_log "zero_tasks" "SKIP_LOGGED" "phase_has_no_actionable_tasks_plans=$plan_count" \
    "{\"phase_dir\":\"$phase_dir\",\"plan_count\":$plan_count}"
  echo "SKIP_LOGGED"
  return 0
}

# === Dispatch failure decision ===
# Args: error_blob_or_path retry_count
# Emits: RETRY_NEXT_TIER | SELF_HEAL | ESCALATE_REPEATED
policy_dispatch_failure() {
  local error_ref="${1:-unknown}"
  local retry_count="${2:-0}"

  if [[ "$retry_count" -ge "$ARK_SELF_HEAL_MAX" ]]; then
    _policy_log "dispatch_failure" "ESCALATE_REPEATED" \
      "retries_${retry_count}_exhausted_max_${ARK_SELF_HEAL_MAX}" \
      "{\"error_ref\":\"$error_ref\"}"
    echo "ESCALATE_REPEATED"
    return 2
  fi

  if [[ "$retry_count" -eq 0 ]]; then
    _policy_log "dispatch_failure" "RETRY_NEXT_TIER" "first_failure_try_next_dispatcher" \
      "{\"error_ref\":\"$error_ref\"}"
    echo "RETRY_NEXT_TIER"
    return 0
  fi

  _policy_log "dispatch_failure" "SELF_HEAL" "retry_${retry_count}_attempt_self_heal" \
    "{\"error_ref\":\"$error_ref\"}"
  echo "SELF_HEAL"
  return 0
}

# === Audit helper (public): show recent decisions ===
policy_audit() {
  local n="${1:-20}"
  if [[ ! -f "$POLICY_LOG" ]]; then
    echo "No policy decisions logged yet."
    return
  fi
  tail -n "$n" "$POLICY_LOG"
}

# === Self-test (only runs when sourced with $1=test) ===
if [[ "${1:-}" == "test" ]]; then
  echo "🧪 ark-policy.sh self-test"
  echo ""

  # Backup log so test doesn't pollute prod
  TEST_LOG="/tmp/ark-policy-test-$$.jsonl"
  POLICY_LOG="$TEST_LOG"

  pass=0
  fail=0

  assert_eq() {
    local expected="$1"
    local actual="$2"
    local label="$3"
    if [[ "$expected" == "$actual" ]]; then
      echo "  ✅ $label"
      pass=$((pass+1))
    else
      echo "  ❌ $label  (expected: $expected, got: $actual)"
      fail=$((fail+1))
    fi
  }

  echo "Budget decisions:"
  assert_eq "PROCEED"               "$(policy_budget_decision 1000 50000 10000 1000000)"   "under cap"
  assert_eq "AUTO_RESET"            "$(policy_budget_decision 60000 50000 60000 1000000)"  "phase cap hit, monthly OK"
  assert_eq "ESCALATE_MONTHLY_CAP"  "$(policy_budget_decision 60000 50000 960000 1000000)" "monthly >=95%"

  echo ""
  echo "Dispatcher routing:"
  ARK_FORCE_QUOTA_CODEX=true ARK_FORCE_QUOTA_GEMINI=true \
    assert_eq "regex-fallback" "$(ARK_FORCE_QUOTA_CODEX=true ARK_FORCE_QUOTA_GEMINI=true policy_dispatcher_route standard BLACK)" "BLACK tier → fallback"

  echo ""
  echo "Zero-task decision:"
  assert_eq "SKIP_LOGGED" "$(policy_zero_tasks /tmp/fake-phase 0)" "phase with no tasks → skip"

  echo ""
  echo "Dispatch failure:"
  assert_eq "RETRY_NEXT_TIER"     "$(policy_dispatch_failure /tmp/err 0)" "first failure"
  assert_eq "SELF_HEAL"           "$(policy_dispatch_failure /tmp/err 1)" "retry 1"
  assert_eq "ESCALATE_REPEATED"   "$(policy_dispatch_failure /tmp/err 3)" "retry 3 = exhausted"

  echo ""
  echo "Audit log entries: $(wc -l < "$TEST_LOG" | tr -d ' ')"

  echo ""
  if [[ "$fail" -eq 0 ]]; then
    echo "✅ ALL POLICY TESTS PASSED ($pass/$pass)"
    rm -f "$TEST_LOG"
    exit 0
  else
    echo "❌ $fail/$((pass+fail)) tests failed"
    exit 1
  fi
fi
