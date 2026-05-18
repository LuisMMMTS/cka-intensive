#!/usr/bin/env bash
# Smoke test for Lab 6d — Kustomize.
# Covers: base + dev/prod overlays via kubectl apply -k, image/replica
# patches, configMapGenerator hash-suffixed naming.

set -uo pipefail

LAB=lab6d
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/assertions.sh
source "$SCRIPT_DIR/lib/assertions.sh"

# Lab uses cluster-scoped namespaces (dev, prod) — use unique suffixes
DEV_NS="lab6d-dev-$RANDOM"
PROD_NS="lab6d-prod-$RANDOM"
WORK=$(mktemp -d)

lab6d_cleanup() {
  kubectl delete ns "$DEV_NS" "$PROD_NS" --wait=false --ignore-not-found=true >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap lab6d_cleanup EXIT

mkdir -p "$WORK/base" "$WORK/overlays/dev" "$WORK/overlays/prod"

cat > "$WORK/base/deployment.yaml" <<EOF
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
        - name: web
          image: nginx:1.27
          ports: [{ containerPort: 80 }]
          env: [{ name: LOG_LEVEL, value: info }]
EOF
cat > "$WORK/base/service.yaml" <<EOF
apiVersion: v1
kind: Service
metadata: { name: web }
spec:
  selector: { app: web }
  ports: [{ port: 80, targetPort: 80 }]
EOF
cat > "$WORK/base/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources: [deployment.yaml, service.yaml]
commonLabels: { app: web }
EOF
cat > "$WORK/overlays/dev/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: $DEV_NS
resources: [../../base]
images: [{ name: nginx, newTag: "1.27-alpine" }]
patches:
  - target: { kind: Deployment, name: web }
    patch: |
      - op: replace
        path: /spec/replicas
        value: 1
EOF
cat > "$WORK/overlays/prod/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: $PROD_NS
resources: [../../base]
images: [{ name: nginx, newTag: "1.28" }]
patches:
  - target: { kind: Deployment, name: web }
    patch: |
      - op: replace
        path: /spec/replicas
        value: 5
      - op: replace
        path: /spec/template/spec/containers/0/env/0/value
        value: warn
configMapGenerator:
  - name: env
    literals:
      - REGION=us-east-1
      - TIER=production
EOF

# kustomize render only (sanity)
if kubectl kustomize "$WORK/overlays/prod" >/dev/null 2>&1; then
  pass "kubectl kustomize renders prod overlay"
else
  fail "kubectl kustomize FAILED on prod overlay"
  finish; exit
fi

kubectl create ns "$DEV_NS" >/dev/null
kubectl create ns "$PROD_NS" >/dev/null

log "apply dev overlay"
kubectl apply -k "$WORK/overlays/dev" >/dev/null
log "apply prod overlay"
kubectl apply -k "$WORK/overlays/prod" >/dev/null

# Assertions on dev
TEST_NAMESPACE="$DEV_NS"
assert_deployment_available web 90s
replicas=$(kubectl -n "$DEV_NS" get deploy web -o jsonpath='{.spec.replicas}')
image=$(kubectl -n "$DEV_NS" get deploy web -o jsonpath='{.spec.template.spec.containers[0].image}')
[ "$replicas" = "1" ] && pass "dev: replicas=1" || fail "dev: replicas=$replicas"
[ "$image" = "nginx:1.27-alpine" ] && pass "dev: image=nginx:1.27-alpine" || fail "dev: image=$image"

# Assertions on prod
TEST_NAMESPACE="$PROD_NS"
assert_deployment_available web 90s
replicas=$(kubectl -n "$PROD_NS" get deploy web -o jsonpath='{.spec.replicas}')
image=$(kubectl -n "$PROD_NS" get deploy web -o jsonpath='{.spec.template.spec.containers[0].image}')
envval=$(kubectl -n "$PROD_NS" get deploy web -o jsonpath='{.spec.template.spec.containers[0].env[0].value}')
[ "$replicas" = "5" ] && pass "prod: replicas=5" || fail "prod: replicas=$replicas"
[ "$image" = "nginx:1.28" ] && pass "prod: image=nginx:1.28" || fail "prod: image=$image"
[ "$envval" = "warn" ] && pass "prod: LOG_LEVEL=warn" || fail "prod: LOG_LEVEL=$envval"

# configMapGenerator: ConfigMap exists with hash suffix
cm=$(kubectl -n "$PROD_NS" get cm -o jsonpath='{.items[?(@.metadata.labels.app=="web")].metadata.name}')
if echo "$cm" | grep -qE '^env-[a-z0-9]{10}'; then
  pass "configMapGenerator created hash-suffixed ConfigMap ($cm)"
else
  fail "no hash-suffixed ConfigMap found (got: $cm)"
fi

finish
