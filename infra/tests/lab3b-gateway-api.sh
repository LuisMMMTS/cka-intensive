#!/usr/bin/env bash
# Smoke test for Lab 3b — Gateway API.
# Lab assumes the trainer has pre-installed Gateway API CRDs + Contour.
# If neither is present, the test skips gracefully (exit 0, no assertions).
#
# When pre-installed: creates v1/v2 backends, Gateway, HTTPRoute with 80/20
# split + header-routing rule; asserts Gateway becomes Programmed and the
# header rule pins to v2.

set -uo pipefail

LAB=lab3b
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/assertions.sh
source "$SCRIPT_DIR/lib/assertions.sh"

if ! kubectl get crd gateways.gateway.networking.k8s.io >/dev/null 2>&1; then
  log "Gateway API CRDs not installed — skipping (trainer prereq)"
  exit 0
fi
if ! kubectl get ns projectcontour >/dev/null 2>&1; then
  log "Contour not installed (no projectcontour namespace) — skipping"
  exit 0
fi

setup_namespace lab3b-smoke

log "creating v1 + v2 deployments"
kubectl -n "$TEST_NAMESPACE" create deploy v1 --image=hashicorp/http-echo --replicas=2 -- -text="v1" >/dev/null
kubectl -n "$TEST_NAMESPACE" create deploy v2 --image=hashicorp/http-echo --replicas=2 -- -text="v2" >/dev/null
kubectl -n "$TEST_NAMESPACE" expose deploy v1 --port=80 --target-port=5678 >/dev/null
kubectl -n "$TEST_NAMESPACE" expose deploy v2 --port=80 --target-port=5678 >/dev/null
assert_deployment_available v1
assert_deployment_available v2

log "creating Gateway app-gw"
kubectl apply -f - >/dev/null <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata: { name: app-gw, namespace: $TEST_NAMESPACE }
spec:
  gatewayClassName: contour
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      allowedRoutes:
        namespaces: { from: Same }
EOF

# Wait for Programmed=True
for i in $(seq 1 30); do
  prog=$(kubectl -n "$TEST_NAMESPACE" get gateway app-gw -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null)
  [ "$prog" = "True" ] && break
  sleep 2
done
[ "${prog:-}" = "True" ] && pass "Gateway app-gw Programmed=True" || fail "Gateway app-gw not Programmed within 60s"

log "creating HTTPRoute with header rule + 80/20 split"
kubectl apply -f - >/dev/null <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: { name: app, namespace: $TEST_NAMESPACE }
spec:
  parentRefs: [{ name: app-gw }]
  hostnames: [app.local]
  rules:
    - matches:
        - path: { type: PathPrefix, value: / }
          headers: [{ name: x-version, value: v2 }]
      backendRefs: [{ name: v2, port: 80 }]
    - matches:
        - path: { type: PathPrefix, value: / }
      backendRefs:
        - { name: v1, port: 80, weight: 80 }
        - { name: v2, port: 80, weight: 20 }
EOF
sleep 5

# Get Envoy/Contour service ClusterIP
envoy_ip=$(kubectl -n projectcontour get svc envoy -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
[ -n "$envoy_ip" ] && pass "Envoy ClusterIP discovered ($envoy_ip)" \
  || { fail "Envoy service not found in projectcontour ns"; finish; exit; }

create_test_pod curler

log "header-routed request pins to v2"
out=$(kubectl -n "$TEST_NAMESPACE" exec curler -- \
  wget -qO- -S --timeout=8 --header='Host: app.local' --header='x-version: v2' "http://$envoy_ip/" 2>&1 || true)
if echo "$out" | grep -q '^v2$'; then
  pass "x-version: v2 header → v2 backend"
else
  fail "header rule did NOT pin to v2 (got: $(echo "$out" | head -1))"
fi

log "default rule splits between v1/v2 (sample 20 requests)"
v1=0; v2=0
for i in $(seq 1 20); do
  r=$(kubectl -n "$TEST_NAMESPACE" exec curler -- \
    wget -qO- --timeout=4 --header='Host: app.local' "http://$envoy_ip/" 2>/dev/null || true)
  [ "$r" = "v1" ] && v1=$((v1+1))
  [ "$r" = "v2" ] && v2=$((v2+1))
done
# Don't assert exact ratios (small sample), just that both backends got some hits
if [ "$v1" -gt 0 ] && [ "$v2" -gt 0 ]; then
  pass "split rule sends to both v1 ($v1/20) and v2 ($v2/20)"
else
  fail "split rule did not hit both backends (v1=$v1 v2=$v2)"
fi

finish
