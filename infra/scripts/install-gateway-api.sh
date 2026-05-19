#!/usr/bin/env bash
# Install the Gateway API CRDs + Contour controller into the current kind
# cluster. Lab 3b on Day 2 assumes both are present; this script is the
# "pre-install" the lab refers to.
#
# Idempotent. Run as the trainee user (uses kubeconfig at ~/.kube/config).
#
# Usage:
#   ./install-gateway-api.sh             # install
#   ./install-gateway-api.sh --uninstall # remove (for clean reset before mock)

set -uo pipefail

GATEWAY_API_VERSION="${GATEWAY_API_VERSION:-v1.2.0}"
CONTOUR_MANIFEST="${CONTOUR_MANIFEST:-https://projectcontour.io/quickstart/contour-gateway-provisioner.yaml}"

log()  { printf '\033[36m[gateway-api]\033[0m %s\n' "$*"; }
die()  { printf '\033[31m[gateway-api]\033[0m %s\n' "$*" >&2; exit 1; }

command -v kubectl >/dev/null || die "kubectl not installed"
kubectl cluster-info >/dev/null 2>&1 || die "kubectl can't reach a cluster"

if [ "${1:-}" = "--uninstall" ]; then
  log "removing Contour"
  kubectl delete -f "$CONTOUR_MANIFEST" --ignore-not-found=true --wait=false
  log "removing Gateway API CRDs"
  kubectl delete -f \
    "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml" \
    --ignore-not-found=true --wait=false
  log "done"
  exit 0
fi

# ----- 1. Gateway API CRDs -------------------------------------------------

if kubectl get crd gateways.gateway.networking.k8s.io >/dev/null 2>&1; then
  log "Gateway API CRDs already installed, skipping"
else
  log "installing Gateway API CRDs (${GATEWAY_API_VERSION}, standard channel)"
  kubectl apply -f \
    "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"
  log "waiting for CRDs to be Established (up to 60s)"
  kubectl wait --for condition=established --timeout=60s \
    crd/gatewayclasses.gateway.networking.k8s.io \
    crd/gateways.gateway.networking.k8s.io \
    crd/httproutes.gateway.networking.k8s.io
fi

# ----- 2. Contour controller (Gateway-API provisioner mode) ---------------

if kubectl get ns projectcontour >/dev/null 2>&1; then
  log "Contour already installed (projectcontour ns exists), skipping"
else
  log "installing Contour Gateway provisioner"
  kubectl apply -f "$CONTOUR_MANIFEST"
  log "waiting for Contour controller pods (up to 3 min)"
  kubectl -n projectcontour wait --for=condition=Available deploy --all --timeout=180s \
    || log "WARN: Contour Deployments not all Available — check 'kubectl -n projectcontour get pods'"
fi

# ----- 3. GatewayClass 'contour' (so Lab 3b's gatewayClassName works) -----

if kubectl get gatewayclass contour >/dev/null 2>&1; then
  log "GatewayClass 'contour' already exists"
else
  log "creating GatewayClass 'contour'"
  kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata: { name: contour }
spec:
  controllerName: projectcontour.io/gateway-controller
EOF
fi

log ""
log "=============================================================="
log "Gateway API + Contour ready. Lab 3b can run."
log ""
log "Verify:"
log "  kubectl get crd | grep gateway.networking.k8s.io"
log "  kubectl -n projectcontour get pods"
log "  kubectl get gatewayclass"
log "=============================================================="
