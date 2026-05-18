#!/usr/bin/env bash
# Smoke test for Lab 5b — ResourceQuota & LimitRange.
# Covers: quota applied, replicas capped at quota limit, quota requires
# resource requests, LimitRange injects defaults so pods become admissible.

set -uo pipefail

LAB=lab5b
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/assertions.sh
source "$SCRIPT_DIR/lib/assertions.sh"

setup_namespace lab5b-smoke

# ----- 5b.1 apply quota -----------------------------------------------------

log "applying ResourceQuota ns-quota (5 pods, 2 CPU req, 1Gi mem req)"
kubectl -n "$TEST_NAMESPACE" apply -f - >/dev/null <<EOF
apiVersion: v1
kind: ResourceQuota
metadata: { name: ns-quota }
spec:
  hard:
    requests.cpu: "2"
    requests.memory: 1Gi
    limits.cpu: "4"
    limits.memory: 2Gi
    pods: "5"
EOF
assert_resource_exists resourcequota ns-quota

# ----- 5b.2 quota requires requests (pod rejected without them) -----------

log "deploy 'hog' without resources block (should be rejected — quota tracks requests.cpu)"
kubectl -n "$TEST_NAMESPACE" create deploy hog --image=nginx:1.27 --replicas=2 >/dev/null

# Wait for the ReplicaSet controller to log a failure event
sleep 10

# Pods should NOT exist (or be 0 ready) because the RS controller is being
# blocked by the quota requiring requests.cpu.
ready=$(kubectl -n "$TEST_NAMESPACE" get deploy hog -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
ready="${ready:-0}"
if [ "$ready" = "0" ]; then
  pass "deploy/hog blocked by quota (0 ready replicas, requests.cpu missing)"
else
  fail "deploy/hog has $ready ready replicas — quota should have blocked"
fi

# Check the ReplicaSet for a 'must specify' event
if kubectl -n "$TEST_NAMESPACE" describe rs -l app=hog 2>/dev/null | grep -qE 'must specify|forbidden.*quota'; then
  pass "ReplicaSet shows quota rejection event"
else
  fail "no quota rejection event visible on ReplicaSet"
fi

kubectl -n "$TEST_NAMESPACE" delete deploy hog --wait=false >/dev/null

# ----- 5b.4 LimitRange injects defaults ------------------------------------

log "applying LimitRange (defaults so pods become admissible)"
kubectl -n "$TEST_NAMESPACE" apply -f - >/dev/null <<EOF
apiVersion: v1
kind: LimitRange
metadata: { name: defaults }
spec:
  limits:
    - type: Container
      default:        { cpu: 200m, memory: 256Mi }
      defaultRequest: { cpu: 100m, memory: 128Mi }
EOF

log "re-deploy 'hog' (no resources block) — LimitRange should inject defaults"
kubectl -n "$TEST_NAMESPACE" create deploy hog --image=nginx:1.27 --replicas=2 >/dev/null
assert_deployment_available hog 60s

# Verify a pod has the injected requests
pod=$(kubectl -n "$TEST_NAMESPACE" get pods -l app=hog -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$pod" ]; then
  cpu_req=$(kubectl -n "$TEST_NAMESPACE" get pod "$pod" -o jsonpath='{.spec.containers[0].resources.requests.cpu}' 2>/dev/null)
  if [ "$cpu_req" = "100m" ]; then
    pass "LimitRange injected requests.cpu=100m into pod"
  else
    fail "LimitRange did NOT inject defaults (cpu_req=$cpu_req)"
  fi
fi

# ----- 5b.2-ish: pod count cap ---------------------------------------------

log "trying to scale 'hog' to 6 (quota caps at 5 pods)"
kubectl -n "$TEST_NAMESPACE" scale deploy hog --replicas=6 >/dev/null
sleep 10
total_pods=$(kubectl -n "$TEST_NAMESPACE" get pods --no-headers 2>/dev/null | grep -v Terminating | wc -l | tr -d ' ')
if [ "$total_pods" -le 5 ]; then
  pass "pod count capped at $total_pods (quota limit 5)"
else
  fail "pod count $total_pods exceeds quota limit 5"
fi

finish
