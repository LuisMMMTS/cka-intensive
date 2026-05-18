#!/usr/bin/env bash
# Smoke test for Lab 3 — Services & Ingress.
# Covers: ClusterIP, NodePort, headless service, and ingress-nginx routing.
# Installs ingress-nginx if not already present (cluster-wide, kept after).

set -uo pipefail

LAB=lab3
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/assertions.sh
source "$SCRIPT_DIR/lib/assertions.sh"

setup_namespace lab3-smoke

# ----- 3.1/3.2/3.3 ClusterIP, NodePort, headless ---------------------------

log "Deployment web + ClusterIP service"
kubectl -n "$TEST_NAMESPACE" create deploy web --image=nginx:1.27 --replicas=2 >/dev/null
kubectl -n "$TEST_NAMESPACE" expose deploy web --port=80 >/dev/null
assert_deployment_available web
wait_for_endpoints web

create_test_pod tmp
assert_http_from_pod_succeeds tmp "http://web.$TEST_NAMESPACE.svc.cluster.local"

log "NodePort service"
kubectl -n "$TEST_NAMESPACE" expose deploy web --name=web-np --type=NodePort --port=80 >/dev/null
assert_resource_exists service web-np
np=$(kubectl -n "$TEST_NAMESPACE" get svc web-np -o jsonpath='{.spec.ports[0].nodePort}')
[ -n "$np" ] && pass "NodePort allocated ($np)" || fail "NodePort not allocated"

log "headless service"
kubectl -n "$TEST_NAMESPACE" apply -f - >/dev/null <<EOF
apiVersion: v1
kind: Service
metadata: { name: web-headless }
spec:
  clusterIP: None
  selector: { app: web }
  ports: [{ port: 80 }]
EOF
if kubectl -n "$TEST_NAMESPACE" exec tmp -- nslookup "web-headless.$TEST_NAMESPACE.svc.cluster.local" 2>/dev/null \
    | grep -qE 'Address.*192\.168\.'; then
  pass "headless service resolves to pod IPs"
else
  fail "headless service did NOT resolve to pod IPs"
fi

# ----- 3.4 ingress-nginx + Ingress object ---------------------------------

if kubectl get ns ingress-nginx >/dev/null 2>&1 \
    && kubectl -n ingress-nginx get deploy ingress-nginx-controller >/dev/null 2>&1; then
  pass "ingress-nginx already installed, skipping install"
else
  log "installing ingress-nginx (kind manifest, ~30s)"
  kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml >/dev/null
  log "waiting for ingress-nginx controller Ready"
  if kubectl wait -n ingress-nginx --for=condition=Ready pod \
      --selector=app.kubernetes.io/component=controller --timeout=180s >/dev/null 2>&1; then
    pass "ingress-nginx controller Ready"
  else
    fail "ingress-nginx controller did NOT become Ready"
  fi
fi

# The admission webhook is a separate Service that takes a few seconds to
# wire up after the controller pod is Ready. Applying an Ingress before
# the webhook is up fails with "connection refused".
log "waiting for ingress-nginx admission webhook endpoints"
for i in $(seq 1 30); do
  if kubectl -n ingress-nginx get endpoints ingress-nginx-controller-admission \
      -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null | grep -q .; then
    pass "admission webhook endpoints ready"
    break
  fi
  sleep 2
done

log "Ingress object web.cka.local → svc/web"
kubectl -n "$TEST_NAMESPACE" apply -f - >/dev/null <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata: { name: web }
spec:
  ingressClassName: nginx
  rules:
    - host: web.cka.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: web
                port: { number: 80 }
EOF

# Don't assert on status.loadBalancer.ingress[].ip — kind's ingress-nginx
# provider doesn't have a real cloud LB, so that field never populates.
# The actual proof of correctness is the curl below.
#
# The controller needs a few seconds to reconcile the Ingress object into
# its nginx config (separate from the admission-webhook readiness we
# already waited for). Retry the curl with a longer wait window.
log "curling Ingress through localhost (with retries while controller reconciles)"
ingress_ok=0
for attempt in $(seq 1 8); do
  if curl -sfH 'Host: web.cka.local' -m 5 http://localhost 2>/dev/null | grep -q 'Welcome to nginx'; then
    ingress_ok=1; break
  fi
  sleep 3
done

if [ "$ingress_ok" = 1 ]; then
  pass "Ingress routes web.cka.local → nginx welcome page (attempt $attempt)"
else
  fail "Ingress did NOT route correctly after ~25s — diagnosing:"
  echo "  --- curl response code ---"
  code=$(curl -sH 'Host: web.cka.local' -m 5 -o /dev/null -w '%{http_code}' http://localhost 2>/dev/null || echo "(no response)")
  echo "    HTTP $code"
  echo "  --- Ingress object ---"
  kubectl -n "$TEST_NAMESPACE" get ingress web -o wide 2>/dev/null | sed 's/^/    /'
  echo "  --- IngressClass ---"
  kubectl get ingressclass nginx -o jsonpath='{.spec.controller}{"\n"}' 2>/dev/null | sed 's/^/    /'
  echo "  --- controller pod (node + status) ---"
  kubectl -n ingress-nginx get pods -l app.kubernetes.io/component=controller -o wide 2>/dev/null | sed 's/^/    /'
  echo "  --- Ingress events ---"
  kubectl -n "$TEST_NAMESPACE" describe ingress web 2>/dev/null | tail -10 | sed 's/^/    /'
fi

finish
