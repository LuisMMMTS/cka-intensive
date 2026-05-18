#!/usr/bin/env bash
# Smoke test for Lab 4 — NetworkPolicy.
# Asserts that Calico actually enforces NetworkPolicy on the kind cluster:
# - baseline: frontend/backend Services reachable
# - default-deny: all traffic blocked
# - selective allow: only pods labeled app=frontend can reach backend

set -uo pipefail

LAB=lab4
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/assertions.sh
source "$SCRIPT_DIR/lib/assertions.sh"

setup_namespace lab4-smoke

# ----- 4.1 setup: two deployments + services -------------------------------

log "creating frontend + backend deployments"
kubectl -n "$TEST_NAMESPACE" apply -f - >/dev/null <<EOF
apiVersion: apps/v1
kind: Deployment
metadata: { name: frontend, labels: { app: frontend } }
spec:
  replicas: 1
  selector: { matchLabels: { app: frontend } }
  template:
    metadata: { labels: { app: frontend } }
    spec:
      containers: [{ name: nginx, image: nginx:1.27, ports: [{ containerPort: 80 }] }]
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: backend, labels: { app: backend } }
spec:
  replicas: 1
  selector: { matchLabels: { app: backend } }
  template:
    metadata: { labels: { app: backend } }
    spec:
      containers: [{ name: nginx, image: nginx:1.27, ports: [{ containerPort: 80 }] }]
EOF

kubectl -n "$TEST_NAMESPACE" expose deploy frontend --port=80 >/dev/null
kubectl -n "$TEST_NAMESPACE" expose deploy backend  --port=80 >/dev/null

assert_deployment_available frontend
assert_deployment_available backend
wait_for_endpoints frontend
wait_for_endpoints backend

# Long-lived test pods: 'tmp' (no labels) and 'f' (labeled app=frontend).
# Created once; subsequent assertions use kubectl exec — far more reliable
# than per-test 'kubectl run --rm' pods, which have shell-quoting and
# Calico WorkloadEndpoint-timing pitfalls.
log "creating long-lived test pods (tmp, f)"
create_test_pod tmp
create_test_pod f "app=frontend"

# ----- baseline: no NetworkPolicy yet --------------------------------------

log "baseline: tmp can reach both services"
assert_http_from_pod_succeeds tmp "http://frontend.$TEST_NAMESPACE.svc.cluster.local"
assert_http_from_pod_succeeds tmp "http://backend.$TEST_NAMESPACE.svc.cluster.local"

# ----- 4.2 default-deny -----------------------------------------------------

log "applying default-deny ingress NetworkPolicy"
kubectl -n "$TEST_NAMESPACE" apply -f - >/dev/null <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: default-deny }
spec:
  podSelector: {}
  policyTypes: [Ingress]
EOF
sleep 3   # give Calico time to program iptables/eBPF
assert_http_from_pod_fails tmp "http://frontend.$TEST_NAMESPACE.svc.cluster.local"
assert_http_from_pod_fails tmp "http://backend.$TEST_NAMESPACE.svc.cluster.local"

# ----- 4.3 selective allow: frontend → backend -----------------------------

log "applying allow-frontend-to-backend NetworkPolicy"
kubectl -n "$TEST_NAMESPACE" apply -f - >/dev/null <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: allow-frontend-to-backend }
spec:
  podSelector: { matchLabels: { app: backend } }
  policyTypes: [Ingress]
  ingress:
    - from:
        - podSelector: { matchLabels: { app: frontend } }
      ports:
        - protocol: TCP
          port: 80
EOF
sleep 3

# Unlabeled pod still blocked (only the allow-rule grants access)
log "unlabeled pod still blocked from backend"
assert_http_from_pod_fails tmp "http://backend.$TEST_NAMESPACE.svc.cluster.local"

# Labeled pod allowed
log "labeled frontend pod allowed to reach backend"
assert_http_from_pod_succeeds f "http://backend.$TEST_NAMESPACE.svc.cluster.local"

finish
