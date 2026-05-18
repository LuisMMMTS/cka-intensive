#!/usr/bin/env bash
# Smoke test for Lab 6e — HPA.
# Covers: metrics-server reachable (`k top` works), Deployment with
# requests, HPA created, generates load with `hey`, HPA scales replicas
# above min under load. Skip-load-test mode available via env var.

set -uo pipefail

LAB=lab6e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/assertions.sh
source "$SCRIPT_DIR/lib/assertions.sh"

setup_namespace lab6e-smoke

# ----- 6e.1 metrics-server already installed by kind-bootstrap.sh ----------

if kubectl -n kube-system get deploy metrics-server >/dev/null 2>&1; then
  pass "metrics-server installed"
else
  fail "metrics-server NOT installed — kind-bootstrap.sh installs it"
  finish; exit
fi

# `kubectl top` may need a scrape cycle to warm up; retry briefly
for i in $(seq 1 12); do
  if kubectl top nodes >/dev/null 2>&1; then break; fi
  sleep 5
done
if kubectl top nodes >/dev/null 2>&1; then
  pass "kubectl top nodes works (metrics-server serving)"
else
  fail "kubectl top nodes never started working"
fi

# ----- 6e.2 Deployment with requests ---------------------------------------

log "Deployment 'web' with cpu requests"
kubectl -n "$TEST_NAMESPACE" apply -f - >/dev/null <<EOF
apiVersion: apps/v1
kind: Deployment
metadata: { name: web }
spec:
  replicas: 1
  selector: { matchLabels: { app: web } }
  template:
    metadata: { labels: { app: web } }
    spec:
      containers:
        - name: nginx
          image: nginx:1.27
          ports: [{ containerPort: 80 }]
          resources:
            requests: { cpu: 100m, memory: 64Mi }
            limits:   { cpu: 200m, memory: 128Mi }
EOF
kubectl -n "$TEST_NAMESPACE" expose deploy web --port=80 >/dev/null
assert_deployment_available web 90s

# ----- 6e.3 HPA ------------------------------------------------------------

log "creating HPA (min=2 max=10 cpu=50%)"
kubectl -n "$TEST_NAMESPACE" autoscale deploy web --min=2 --max=10 --cpu-percent=50 >/dev/null
assert_resource_exists hpa web

# Wait for HPA to scale up from 1 → 2 (min)
for i in $(seq 1 30); do
  r=$(kubectl -n "$TEST_NAMESPACE" get deploy web -o jsonpath='{.spec.replicas}')
  [ "$r" -ge 2 ] && break
  sleep 2
done
[ "$r" -ge 2 ] && pass "HPA scaled to min=2 ($r replicas)" \
  || fail "HPA did NOT scale to min=2 (still $r)"

# ----- 6e.4/.5 Load test (skip if SKIP_LOAD_TEST=1) ------------------------

if [ "${SKIP_LOAD_TEST:-0}" = "1" ]; then
  log "SKIP_LOAD_TEST=1 → skipping the load-test phase"
  finish; exit
fi

log "load test with 'hey' for 60s (set SKIP_LOAD_TEST=1 to skip)"
kubectl -n "$TEST_NAMESPACE" run hey --image=ghcr.io/rakyll/hey --restart=Never \
  --command -- -z 60s -c 100 "http://web.$TEST_NAMESPACE.svc.cluster.local" >/dev/null

# Monitor HPA for up to 90s, expect replicas to climb past min
peak=$(kubectl -n "$TEST_NAMESPACE" get deploy web -o jsonpath='{.spec.replicas}')
for i in $(seq 1 18); do
  sleep 5
  r=$(kubectl -n "$TEST_NAMESPACE" get deploy web -o jsonpath='{.spec.replicas}' 2>/dev/null)
  [ -n "$r" ] && [ "$r" -gt "$peak" ] && peak=$r
  [ "$peak" -ge 3 ] && break
done

if [ "$peak" -ge 3 ]; then
  pass "HPA scaled up under load (peak=$peak replicas)"
else
  # Not always reproducible — load timing, metrics scrape lag, kind CPU
  fail "HPA did not scale past min within 90s (peak=$peak) — metrics lag or low load"
fi

# Don't wait for scale-down (5min stabilization window) — finish quickly
kubectl -n "$TEST_NAMESPACE" delete pod hey --wait=false --ignore-not-found=true >/dev/null 2>&1 || true

finish
