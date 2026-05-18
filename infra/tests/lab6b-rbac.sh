#!/usr/bin/env bash
# Smoke test for Lab 6b — RBAC.
# Covers: SA + Role + RoleBinding (namespaced) + ClusterRole + ClusterRoleBinding
# (cluster-wide). Verifies access by building an SA kubeconfig and actually
# performing operations with it — avoids the impersonation + redacted-CA
# gotchas of `auth can-i --as=` + `kubectl config view` without --raw.
# Cleans up cluster-scoped resources in trap.

set -uo pipefail

LAB=lab6b
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/assertions.sh
source "$SCRIPT_DIR/lib/assertions.sh"

SUFFIX=$RANDOM
CR="node-viewer-$SUFFIX"
CRB="dev-cluster-binding-$SUFFIX"
KC=""

lab6b_cleanup() {
  [ -n "$KC" ] && rm -f "$KC"
  kubectl delete clusterrolebinding "$CRB" --wait=false --ignore-not-found=true >/dev/null 2>&1 || true
  kubectl delete clusterrole "$CR"          --wait=false --ignore-not-found=true >/dev/null 2>&1 || true
  cleanup_namespace
}
trap lab6b_cleanup EXIT

setup_namespace lab6b-smoke

# ----- create SA + Role + RoleBinding (namespaced) -------------------------

log "creating SA dev, Role pod-reader, RoleBinding"
kubectl -n "$TEST_NAMESPACE" create sa dev >/dev/null
kubectl -n "$TEST_NAMESPACE" create role pod-reader \
  --verb=get --verb=list --verb=watch \
  --resource=pods --resource=pods/log >/dev/null
kubectl -n "$TEST_NAMESPACE" create rolebinding dev-pod-reader \
  --role=pod-reader --serviceaccount="$TEST_NAMESPACE:dev" >/dev/null

# ----- create ClusterRole + CRB --------------------------------------------

log "creating ClusterRole $CR + ClusterRoleBinding $CRB for SA"
kubectl create clusterrole "$CR" --verb=get --verb=list --verb=watch \
  --resource=nodes >/dev/null
kubectl create clusterrolebinding "$CRB" \
  --clusterrole="$CR" --serviceaccount="$TEST_NAMESPACE:dev" >/dev/null

# ----- build a kubeconfig for the SA ---------------------------------------
# NOTE: must use --raw to get the actual certificate-authority-data (it's
# redacted by default in `kubectl config view`).

log "building SA kubeconfig"
TOKEN=$(kubectl -n "$TEST_NAMESPACE" create token dev --duration=10m)
APISERVER=$(kubectl config view --minify --raw -o jsonpath='{.clusters[0].cluster.server}')
CA=$(kubectl config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')

if [ -z "$TOKEN" ] || [ -z "$APISERVER" ] || [ -z "$CA" ]; then
  fail "could not extract token/apiserver/CA from current kubeconfig"
  finish; exit
fi

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

# ----- verify the SA actually has the access we expect ---------------------

# Helper: returns 0 if KUBECONFIG=$KC succeeds, 1 otherwise
sa() { KUBECONFIG="$KC" kubectl "$@" 2>&1; }

# ALLOWED: list pods in own namespace
if sa get pods >/dev/null 2>&1; then
  pass "SA can list pods in own namespace"
else
  fail "SA CANNOT list pods in own namespace (RBAC: kubectl get pods failed)"
  sa get pods 2>&1 | head -3 | sed 's/^/    /'
fi

# DENIED: delete a pod (any name; we want the RBAC denial, not a "not found")
out=$(sa delete pod nonexistent-pod 2>&1 || true)
if echo "$out" | grep -qi forbidden; then
  pass "SA correctly DENIED delete pods (forbidden response)"
else
  # NotFound means RBAC allowed the verb, just no such pod — that's a fail
  if echo "$out" | grep -qi 'not found'; then
    fail "SA was allowed to delete pods (got NotFound, not Forbidden)"
  else
    fail "unexpected response: $out"
  fi
fi

# DENIED: list pods in default namespace
if sa get pods -n default >/dev/null 2>&1; then
  fail "SA was allowed to list pods in default ns (should be denied)"
else
  pass "SA correctly DENIED listing pods in default namespace"
fi

# ALLOWED: list nodes (via ClusterRoleBinding)
if sa get nodes >/dev/null 2>&1; then
  pass "SA can list nodes (via ClusterRoleBinding $CR)"
else
  fail "SA CANNOT list nodes despite ClusterRoleBinding"
  sa get nodes 2>&1 | head -3 | sed 's/^/    /'
fi

# DENIED: create a deployment
out=$(sa create deploy test --image=nginx:1.27 2>&1 || true)
if echo "$out" | grep -qi forbidden; then
  pass "SA correctly DENIED creating Deployments"
else
  fail "SA was allowed to create a Deployment (unexpected: $out)"
fi

finish
