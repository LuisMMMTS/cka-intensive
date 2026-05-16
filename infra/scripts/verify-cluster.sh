#!/usr/bin/env bash
# Post-bootstrap sanity check for the kind-based cluster. Run after
# ./kind-bootstrap.sh to confirm the cluster works end-to-end (not just
# "Ready" on paper).
#
# Exits 0 if everything passes, 1 if anything fails.

set -uo pipefail

PASS=0
FAIL=0

log()  { printf '\033[36m[verify]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; PASS=$((PASS+1)); }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; FAIL=$((FAIL+1)); }

export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"

# ----- docker + kind --------------------------------------------------------

log "checking docker"
if docker info >/dev/null 2>&1; then
  pass "docker reachable"
else
  fail "docker not reachable (in 'docker' group? daemon running?)"
  exit 1
fi

log "checking kind cluster"
if kind get clusters 2>/dev/null | grep -qx cka; then
  pass "kind cluster 'cka' exists"
else
  fail "kind cluster 'cka' not found"
  exit 1
fi

log "checking node containers"
for n in cka-control-plane cka-worker cka-worker2; do
  if docker inspect "$n" --format '{{.State.Status}}' 2>/dev/null | grep -qx running; then
    pass "container $n running"
  else
    fail "container $n not running"
  fi
done

# ----- kubeconfig + apiserver -----------------------------------------------

log "checking apiserver reachability"
if kubectl get --raw=/healthz >/dev/null 2>&1; then
  pass "apiserver /healthz responding"
else
  fail "apiserver not reachable"
  exit 1
fi

# ----- nodes ----------------------------------------------------------------

log "checking nodes"
ready=$(kubectl get nodes --no-headers 2>/dev/null | awk '$2=="Ready"' | wc -l | tr -d ' ')
if [ "$ready" = "3" ]; then
  pass "3 nodes Ready"
else
  fail "only $ready/3 nodes Ready"
  kubectl get nodes 2>/dev/null || true
fi

if kubectl get nodes -o jsonpath='{.items[*].status.nodeInfo.kubeletVersion}' 2>/dev/null | grep -q 'v1.36'; then
  pass "all nodes at v1.36"
else
  fail "nodes not all at v1.36"
  kubectl get nodes -o wide 2>/dev/null || true
fi

# ----- system pod health ----------------------------------------------------

log "checking system pod health"
for ns in kube-system calico-system; do
  if ! kubectl get ns "$ns" >/dev/null 2>&1; then
    fail "namespace $ns missing"
    continue
  fi
  bad=$(kubectl -n "$ns" get pods --no-headers 2>/dev/null \
        | awk '$3!="Running" && $3!="Completed"' | wc -l | tr -d ' ')
  if [ "$bad" = "0" ]; then
    pass "$ns all pods healthy"
  else
    fail "$ns has $bad non-running pods"
    kubectl -n "$ns" get pods 2>/dev/null | awk 'NR==1 || $3!="Running"'
  fi
done

# ----- metrics-server -------------------------------------------------------

log "checking metrics-server"
if kubectl -n kube-system get deploy metrics-server >/dev/null 2>&1; then
  available=$(kubectl -n kube-system get deploy metrics-server -o jsonpath='{.status.availableReplicas}' 2>/dev/null)
  if [ "$available" = "1" ]; then
    pass "metrics-server available"
    if kubectl top nodes >/dev/null 2>&1; then
      pass "kubectl top nodes works"
    else
      fail "kubectl top nodes failing (warming up? wait 60s and retry)"
    fi
  else
    fail "metrics-server deployment not available"
  fi
else
  fail "metrics-server deployment missing"
fi

# ----- end-to-end smoke test ------------------------------------------------

log "running end-to-end pod test"
NS="verify-$$"
kubectl create ns "$NS" >/dev/null 2>&1 || true
trap "kubectl delete ns $NS --wait=false >/dev/null 2>&1 || true" EXIT

kubectl -n "$NS" run smoke --image=nginx:1.27 --restart=Never >/dev/null 2>&1
if kubectl -n "$NS" wait --for=condition=Ready pod/smoke --timeout=120s >/dev/null 2>&1; then
  pass "test pod ran and became Ready"
else
  fail "test pod did not become Ready in 120s"
  kubectl -n "$NS" describe pod smoke 2>/dev/null | tail -20
fi

# Service + DNS + CNI + kube-proxy all in one test
kubectl -n "$NS" expose pod smoke --port=80 >/dev/null 2>&1
if kubectl -n "$NS" run curl-test --rm -i --restart=Never \
    --image=curlimages/curl --timeout=30s -- \
    curl -sf -m 5 "http://smoke.$NS.svc.cluster.local" 2>/dev/null | grep -q 'Welcome to nginx'; then
  pass "Service DNS + connectivity (CNI + kube-proxy + CoreDNS all working)"
else
  fail "Service connectivity test failed (CNI, kube-proxy, or CoreDNS broken)"
fi

# ----- NetworkPolicy enforcement check --------------------------------------
# (cheap test: applying a default-deny should drop a re-exec curl)

log "checking NetworkPolicy enforcement"
kubectl -n "$NS" apply -f - >/dev/null 2>&1 <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: deny-all }
spec:
  podSelector: {}
  policyTypes: [Ingress]
EOF
sleep 3
if kubectl -n "$NS" run cp-test --rm -i --restart=Never \
    --image=curlimages/curl --timeout=15s -- \
    curl -sf -m 4 "http://smoke.$NS.svc.cluster.local" 2>/dev/null | grep -q 'Welcome'; then
  fail "NetworkPolicy not enforced (kindnet still active? Calico didn't replace it?)"
else
  pass "NetworkPolicy enforced (Calico is the CNI, not kindnet)"
fi

# ----- summary --------------------------------------------------------------

echo
log "summary: $PASS passed, $FAIL failed"
if [ "$FAIL" = "0" ]; then
  log "cluster is ready for class."
  exit 0
else
  log "some checks failed. Read messages above before starting class."
  exit 1
fi
