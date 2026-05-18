#!/usr/bin/env bash
# Run every lab smoke test in sequence on the current cluster.
# Reports pass/fail per lab; exits non-zero if any failed.
#
# Usage:
#   ./run-all-labs.sh                # all labs
#   ./run-all-labs.sh lab2 lab4      # specific labs only

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Order matters: lab N may depend on cluster state from lab N-1's setup phase.
# Each lab script cleans up its own namespace, so re-running is safe.
ALL_LABS=(
  # Day 1
  lab1-kubectl-basics
  lab2-workloads
  lab2b-config-probes
  # Day 2
  lab3-services-ingress
  lab3b-gateway-api
  lab4-networkpolicy
  # Day 3
  lab5-storage
  lab5b-quotas
  lab6-scheduling
  lab6b-rbac
  lab6c-helm
  lab6d-kustomize
  lab6e-hpa
  lab6f-podsecurity
  # Day 4 — lab7 covered by smoke-test-kubeadm.sh; lab8/8b need a kubeadm
  # cluster; lab9 is intentional break/fix (separate framework).
)

# Filter by user-supplied prefixes if given.
if [ "$#" -gt 0 ]; then
  WANT=("$@")
  LABS=()
  for l in "${ALL_LABS[@]}"; do
    for w in "${WANT[@]}"; do
      case "$l" in "$w"*) LABS+=("$l"); break ;; esac
    done
  done
else
  LABS=("${ALL_LABS[@]}")
fi

[ "${#LABS[@]}" -gt 0 ] || { echo "no labs matched"; exit 1; }

RESULTS_PASS=()
RESULTS_FAIL=()
START_ALL=$SECONDS

for lab in "${LABS[@]}"; do
  script="$SCRIPT_DIR/$lab.sh"
  if [ ! -x "$script" ]; then
    echo "  ! $lab: script $script missing/not executable — skipping"
    RESULTS_FAIL+=("$lab (missing)")
    continue
  fi
  echo
  printf '\033[1;35m═══ running %s ═══\033[0m\n' "$lab"
  start=$SECONDS
  if "$script"; then
    dur=$((SECONDS - start))
    RESULTS_PASS+=("$lab (${dur}s)")
  else
    dur=$((SECONDS - start))
    RESULTS_FAIL+=("$lab (${dur}s)")
  fi
done

TOTAL=$((SECONDS - START_ALL))

echo
printf '\033[1;35m═══ run-all-labs summary (%ss) ═══\033[0m\n' "$TOTAL"
echo
echo "passed (${#RESULTS_PASS[@]}):"
for r in "${RESULTS_PASS[@]}"; do printf '  \033[32m✓\033[0m %s\n' "$r"; done
echo
echo "failed (${#RESULTS_FAIL[@]}):"
for r in "${RESULTS_FAIL[@]}"; do printf '  \033[31m✗\033[0m %s\n' "$r"; done

[ "${#RESULTS_FAIL[@]}" -eq 0 ]
