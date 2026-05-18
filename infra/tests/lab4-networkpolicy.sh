#!/usr/bin/env bash
# Smoke test for Lab 4 — NetworkPolicy.
# Asserts that Calico actually enforces NetworkPolicy on the kind cluster:
# - baseline: frontend/backend Services reachable from a tmp pod
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
# Apply with explicit labels on pod template so NetworkPolicy podSelector matches.
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
kubectl -n "$TEST_NAMESPACE" expose deploy backend --port=80 >/dev/null

assert_deployment_available frontend
assert_deployment_available backend

# Wait for Service endpoints to populate. kubectl expose returns immediately
# but the endpoint controller takes a moment to wire the EndpointSlice —
# without this the baseline curl can connect-timeout against an empty Service.
wait_for_endpoints frontend
wait_for_endpoints backend

# Baseline: an unlabeled pod can reach both services (no NetworkPolicy yet)
log "baseline: tmp pod can reach frontend AND backend"
assert_curl_succeeds "http://frontend.$TEST_NAMESPACE.svc.cluster.local"
assert_curl_succeeds "http://backend.$TEST_NAMESPACE.svc.cluster.local"

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
assert_curl_fails "http://frontend.$TEST_NAMESPACE.svc.cluster.local"
assert_curl_fails "http://backend.$TEST_NAMESPACE.svc.cluster.local"

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

# An unlabeled pod still cannot reach backend (only matches the allow rule)
log "unlabeled pod still blocked from backend"
assert_curl_fails "http://backend.$TEST_NAMESPACE.svc.cluster.local"

# A pod labeled app=frontend CAN reach backend
log "labeled frontend pod allowed to reach backend"
assert_curl_succeeds "http://backend.$TEST_NAMESPACE.svc.cluster.local" "app=frontend"

finish
