#!/usr/bin/env bash
# Smoke test for Lab 6b — RBAC.
# Covers: ServiceAccount + Role + RoleBinding (namespaced), ClusterRole +
# ClusterRoleBinding (cluster-wide), auth can-i verification, SA kubeconfig.
# Cleans up cluster-scoped resources in trap (namespace teardown won't catch them).

set -uo pipefail

LAB=lab6b
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/assertions.sh
source "$SCRIPT_DIR/lib/assertions.sh"

# Unique names so concurrent test runs don't collide on cluster-scoped objs
SUFFIX=$RANDOM
CR="node-viewer-$SUFFIX"
CRB="dev-cluster-binding-$SUFFIX"

lab6b_cleanup() {
  kubectl delete clusterrolebinding "$CRB" --wait=false --ignore-not-found=true >/dev/null 2>&1 || true
  kubectl delete clusterrole "$CR"          --wait=false --ignore-not-found=true >/dev/null 2>&1 || true
  cleanup_namespace
}
trap lab6b_cleanup EXIT

setup_namespace lab6b-smoke

# ----- 6b.1 namespaced read-only -------------------------------------------

log "creating SA dev, Role pod-reader, RoleBinding"
kubectl -n "$TEST_NAMESPACE" create sa dev >/dev/null
kubectl -n "$TEST_NAMESPACE" create role pod-reader \
  --verb=get,list,watch --resource=pods,pods/log >/dev/null
kubectl -n "$TEST_NAMESPACE" create rolebinding dev-pod-reader \
  --role=pod-reader --serviceaccount="$TEST_NAMESPACE:dev" >/dev/null

SA="system:serviceaccount:$TEST_NAMESPACE:dev"

# Allowed: list pods in own namespace
if kubectl auth can-i list pods -n "$TEST_NAMESPACE" --as="$SA" 2>/dev/null | grep -qx yes; then
  pass "SA can list pods in own namespace"
else
  fail "SA CANNOT list pods in own namespace"
fi

# Denied: delete pods
if kubectl auth can-i delete pods -n "$TEST_NAMESPACE" --as="$SA" 2>/dev/null | grep -qx no; then
  pass "SA correctly DENIED delete pods"
else
  fail "SA was allowed to delete pods (should be denied)"
fi

# Denied: list pods in different namespace
if kubectl auth can-i list pods -n default --as="$SA" 2>/dev/null | grep -qx no; then
  pass "SA correctly DENIED listing pods in default ns"
else
  fail "SA was allowed to list pods in default ns"
fi

# ----- 6b.3 cluster-wide read on nodes -------------------------------------

log "creating ClusterRole $CR + ClusterRoleBinding $CRB for SA"
kubectl create clusterrole "$CR" --verb=get,list,watch --resource=nodes >/dev/null
kubectl create clusterrolebinding "$CRB" \
  --clusterrole="$CR" --serviceaccount="$TEST_NAMESPACE:dev" >/dev/null

if kubectl auth can-i list nodes --as="$SA" 2>/dev/null | grep -qx yes; then
  pass "SA can list nodes (via ClusterRoleBinding)"
else
  fail "SA CANNOT list nodes despite ClusterRoleBinding"
fi

# ----- 6b.5 build kubeconfig for SA, exercise it ---------------------------

log "build SA kubeconfig and verify access"
TOKEN=$(kubectl -n "$TEST_NAMESPACE" create token dev --duration=10m 2>/dev/null)
APISERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
CA=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')

KC=$(mktemp)
cat > "$KC" <<EOF
apiVersion: v1
kind: Config
clusters:
  - name: cka
    cluster:
      server: $APISERVER
      certificate-authority-data: $CA
users:
  - name: dev
    user: { token: $TOKEN }
contexts:
  - name: dev@cka
    context: { cluster: cka, user: dev, namespace: $TEST_NAMESPACE }
current-context: dev@cka
EOF

if KUBECONFIG="$KC" kubectl get pods >/dev/null 2>&1; then
  pass "SA kubeconfig works for 'k get pods' in own namespace"
else
  fail "SA kubeconfig failed for 'k get pods'"
fi

if KUBECONFIG="$KC" kubectl get nodes >/dev/null 2>&1; then
  pass "SA kubeconfig works for 'k get nodes' (ClusterRole)"
else
  fail "SA kubeconfig failed for 'k get nodes'"
fi

if KUBECONFIG="$KC" kubectl delete pod nonexistent 2>&1 | grep -qE 'forbidden|cannot delete|not found'; then
  # Either Forbidden (good) or NotFound (the verb wasn't even checked because the pod doesn't exist).
  # If it was Forbidden, RBAC blocked us. If NotFound, we got past RBAC — but we expect Forbidden.
  out=$(KUBECONFIG="$KC" kubectl delete pod nonexistent 2>&1 || true)
  if echo "$out" | grep -q forbidden; then
    pass "SA correctly DENIED delete pods via kubeconfig"
  else
    fail "SA was NOT denied delete pods: $out"
  fi
fi

rm -f "$KC"
finish
