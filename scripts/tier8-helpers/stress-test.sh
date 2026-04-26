#!/usr/bin/env bash
# Tier 8 NEW-W-4: 100-call decision_id entropy stress test.
#
# _policy_log echoes its decision_id on stdout. With 64-bit entropy from
# /dev/urandom, collision probability for 100 calls is ~2.7e-17 — effectively zero.
# This test fires 100 calls into an isolated log and asserts uniqueness.

set -uo pipefail

SOURCE_VAULT="${1:-$HOME/vaults/ark}"
STRESS_LOG="$(mktemp -t tier8-stress-XXXXXX.jsonl)"

cleanup() { rm -f "$STRESS_LOG"; }
trap cleanup EXIT

# shellcheck disable=SC1091
source "$SOURCE_VAULT/scripts/ark-policy.sh"
POLICY_LOG="$STRESS_LOG"
: > "$STRESS_LOG"

ids=()
i=0
while [[ $i -lt 100 ]]; do
  ids+=("$(_policy_log stress STRESS_TEST "iter_$i" null)")
  i=$((i+1))
done

UNIQUE=$(printf '%s\n' "${ids[@]}" | sort -u | wc -l | tr -d ' ')
echo "UNIQUE=$UNIQUE"
