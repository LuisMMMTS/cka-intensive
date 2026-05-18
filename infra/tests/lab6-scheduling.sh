#!/usr/bin/env bash
# Smoke test for Lab 6 — Scheduling.
# Covers: nodeSelector, taints + tolerations, resource requests, Pending
# pod with Insufficient memory event. ALWAYS reverses node labels/taints
# in cleanup (trap), since those are cluster-scoped.

set -uo pipefail

LAB=lab6
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/assertions.sh
source "$SCRIPT_DIR/lib/assertions.sh"

# Override the namespace cleanup trap with one that ALSO unlabels and
# untaints the worker node — those changes are cluster-scoped and survive
# namespace deletion otherwise.
NODE_LAB=cka-worker
lab6_cleanup() {
  kubectl label  node "$NODE_LAB" disk-      >/dev/null 2>&1 || true
  kubectl taint  node "$NODE_LAB" dedicated- >/dev/null 2>&1 || true
  cleanup_namespace
}
trap lab6_cleanup EXIT

setup_namespace lab6-smoke

# ----- 6.1 nodeSelector ----------------------------------------------------

log "label cka-worker disk=ssd; pod targets it via nodeSelector"
kubectl label node "$NODE_LAB" disk=ssd --overwrite >/dev/null

kubectl -n "$TEST_NAMESPACE" apply -f - >/dev/null <<EOF
apiVersion: v1
kind: Pod
metadata: { name: ssd-pod }
spec:
  nodeSelector: { disk: ssd }
  containers: [{ name: c, image: nginx:1.27 }]
EOF
assert_pod_ready ssd-pod 60s

actual_node=$(kubectl -n "$TEST_NAMESPACE" get pod ssd-pod -o jsonpath='{.spec.nodeName}')
[ "$actual_node" = "$NODE_LAB" ] && pass "ssd-pod landed on $NODE_LAB" \
  || fail "ssd-pod landed on $actual_node, expected $NODE_LAB"

# ----- 6.2 taints & tolerations --------------------------------------------

log "taint $NODE_LAB dedicated=db:NoSchedule; deploy avoids it"
kubectl taint node "$NODE_LAB" dedicated=db:NoSchedule --overwrite >/dev/null

kubectl -n "$TEST_NAMESPACE" create deploy notol --image=nginx:1.27 --replicas=4 >/dev/null
assert_deployment_available notol 90s

# None of notol's pods should be on the tainted node
on_tainted=$(kubectl -n "$TEST_NAMESPACE" get pods -l app=notol -o jsonpath='{.items[*].spec.nodeName}' \
             | tr ' ' '\n' | grep -c "^$NODE_LAB$" || true)
if [ "$on_tainted" = "0" ]; then
  pass "no notol pods landed on tainted $NODE_LAB"
else
  fail "$on_tainted notol pod(s) on tainted node (should be 0)"
fi

# Now create a deploy WITH toleration — pods should schedule on tainted node
log "deploy 'tolerated' WITH matching toleration → can land on tainted node"
kubectl -n "$TEST_NAMESPACE" apply -f - >/dev/null <<EOF
apiVersion: apps/v1
kind: Deployment
metadata: { name: tolerated }
spec:
  replicas: 2
  selector: { matchLabels: { app: tolerated } }
  template:
    metadata: { labels: { app: tolerated } }
    spec:
      tolerations:
        - { key: dedicated, operator: Equal, value: db, effect: NoSchedule }
      nodeSelector: { disk: ssd }
      containers: [{ name: nginx, image: nginx:1.27 }]
EOF
assert_deployment_available tolerated 90s

# At least one tolerated pod should be on the tainted node
on_tainted=$(kubectl -n "$TEST_NAMESPACE" get pods -l app=tolerated -o jsonpath='{.items[*].spec.nodeName}' \
             | tr ' ' '\n' | grep -c "^$NODE_LAB$" || true)
[ "$on_tainted" -gt 0 ] && pass "tolerated pods scheduled on $NODE_LAB" \
  || fail "tolerated pods did NOT use the tainted node"

# ----- 6.4 Pending due to insufficient memory ------------------------------

log "pod requesting 100Gi memory → Pending with Insufficient memory event"
kubectl -n "$TEST_NAMESPACE" apply -f - >/dev/null <<EOF
apiVersion: v1
kind: Pod
metadata: { name: greedy }
spec:
  containers:
    - name: c
      image: nginx:1.27
      resources: { requests: { memory: 100Gi } }
EOF
sleep 8
phase=$(kubectl -n "$TEST_NAMESPACE" get pod greedy -o jsonpath='{.status.phase}' 2>/dev/null)
if [ "$phase" = "Pending" ]; then
  pass "greedy pod is Pending"
  if kubectl -n "$TEST_NAMESPACE" describe pod greedy 2>/dev/null | grep -qE 'Insufficient memory|FailedScheduling'; then
    pass "scheduling failure event shows Insufficient memory"
  else
    fail "no Insufficient memory event on greedy"
  fi
else
  fail "greedy pod phase=$phase (want Pending)"
fi

finish
