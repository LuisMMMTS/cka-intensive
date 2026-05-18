#!/usr/bin/env bash
# Smoke test for Lab 6c — Helm.
# Covers: repo add, install with overrides, upgrade, rollback, history,
# helm template.

set -uo pipefail

LAB=lab6c
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/assertions.sh
source "$SCRIPT_DIR/lib/assertions.sh"

if ! command -v helm >/dev/null 2>&1; then
  log "helm not installed — skipping lab6c"
  exit 0
fi

# Helm release name + namespace
REL=web-lab6c
NS=lab6c-smoke

# Override default namespace cleanup to also uninstall the helm release
lab6c_cleanup() {
  helm uninstall "$REL" -n "$NS" >/dev/null 2>&1 || true
  kubectl delete ns "$NS" --wait=false --ignore-not-found=true >/dev/null 2>&1 || true
}
trap lab6c_cleanup EXIT

# 6c.1 add repo (idempotent)
log "adding bitnami repo"
helm repo add bitnami https://charts.bitnami.com/bitnami >/dev/null 2>&1 || true
helm repo update >/dev/null
pass "bitnami repo added/updated"

# 6c.2 install
log "helm install $REL bitnami/nginx (--set replicaCount=3)"
if helm install "$REL" bitnami/nginx \
    --namespace "$NS" --create-namespace \
    --set service.type=ClusterIP \
    --set replicaCount=3 \
    --wait --timeout=180s >/dev/null 2>&1; then
  pass "helm install succeeded"
else
  fail "helm install FAILED"
  finish; exit
fi

# Verify deployment replicas
TEST_NAMESPACE="$NS"
dep=$(kubectl -n "$NS" get deploy -l app.kubernetes.io/instance="$REL" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$dep" ]; then
  replicas=$(kubectl -n "$NS" get deploy "$dep" -o jsonpath='{.spec.replicas}')
  [ "$replicas" = "3" ] && pass "deploy/$dep has replicas=3" \
    || fail "deploy/$dep has replicas=$replicas (want 3)"
fi

# 6c.3 helm template (just check it produces YAML, doesn't apply)
if helm template "$REL" bitnami/nginx --set replicaCount=3 2>/dev/null | grep -q '^kind: Deployment'; then
  pass "helm template produces a Deployment"
else
  fail "helm template did NOT produce expected output"
fi

# 6c.4 upgrade to replicaCount=5
log "helm upgrade $REL → replicaCount=5"
if helm upgrade "$REL" bitnami/nginx -n "$NS" --reuse-values --set replicaCount=5 --wait --timeout=180s >/dev/null 2>&1; then
  pass "helm upgrade succeeded"
  replicas=$(kubectl -n "$NS" get deploy "$dep" -o jsonpath='{.spec.replicas}')
  [ "$replicas" = "5" ] && pass "deploy/$dep replicas=5 after upgrade" \
    || fail "deploy/$dep replicas=$replicas (want 5)"
else
  fail "helm upgrade FAILED"
fi

# 6c.5 rollback
log "helm rollback $REL 1 → original install"
if helm rollback "$REL" 1 -n "$NS" --wait --timeout=180s >/dev/null 2>&1; then
  pass "helm rollback succeeded"
  replicas=$(kubectl -n "$NS" get deploy "$dep" -o jsonpath='{.spec.replicas}')
  [ "$replicas" = "3" ] && pass "deploy/$dep replicas=3 after rollback" \
    || fail "deploy/$dep replicas=$replicas (want 3)"
else
  fail "helm rollback FAILED"
fi

# 6c verify: at least 2 revisions visible (install + upgrade; rollback may
# or may not record a new revision depending on helm version)
rev_count=$(helm history "$REL" -n "$NS" 2>/dev/null | grep -cE '^[0-9]')
[ "$rev_count" -ge 2 ] && pass "helm history shows $rev_count revisions" \
  || fail "helm history shows only $rev_count revisions (want ≥ 2)"

finish
