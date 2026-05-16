#!/usr/bin/env bash
# Bootstrap a 3-node Kubernetes cluster using kind (Kubernetes-in-Docker)
# on the trainee's Debian VM.
#
# Cluster name:  cka
# Nodes:         cka-control-plane, cka-worker, cka-worker2
# K8s version:   v1.36.0   (via kindest/node image)
# CNI:           Calico    (replaces kindnet so NetworkPolicy actually enforces)
# Plus:          metrics-server with --kubelet-insecure-tls (for HPA)
#
# Idempotent. Re-running on an already-bootstrapped cluster is a no-op for
# the cluster create; it will re-apply CNI + metrics-server (harmless).
#
# Usage:
#   ./kind-bootstrap.sh                # full bootstrap
#   ./kind-bootstrap.sh --rebuild      # delete the existing cluster first

set -euo pipefail

CLUSTER=cka
K8S_NODE_IMAGE="kindest/node:v1.36.0"
CALICO_VERSION="v3.28.0"
KIND_CONFIG="$(dirname "$0")/kind-config.yaml"

REBUILD=false
for arg in "$@"; do
  case "$arg" in
    --rebuild) REBUILD=true ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    *) echo "unknown flag: $arg" >&2; exit 1 ;;
  esac
done

log()  { printf '\033[36m[bootstrap]\033[0m %s\n' "$*"; }
warn() { printf '\033[33m[bootstrap]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31m[bootstrap]\033[0m %s\n' "$*" >&2; exit 1; }

command -v docker >/dev/null || die "docker not installed"
command -v kind   >/dev/null || die "kind not installed"
command -v kubectl >/dev/null || die "kubectl not installed"

# Ensure docker daemon is reachable without sudo (template should have set
# up the docker group for the user, but check anyway)
if ! docker info >/dev/null 2>&1; then
  die "cannot reach docker daemon — is it running, and are you in the docker group?
       Try: sudo systemctl start docker; sudo usermod -aG docker \$USER; newgrp docker"
fi

# ----- kind config (generated, not checked in) ------------------------------

cat >"$KIND_CONFIG" <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: $CLUSTER
networking:
  # disable kindnet so we can install Calico for real NetworkPolicy enforcement
  disableDefaultCNI: true
  podSubnet: 192.168.0.0/16
nodes:
  - role: control-plane
    image: $K8S_NODE_IMAGE
    # expose 80/443 on the host so Lab 3 ingress works without port-forward
    extraPortMappings:
      - { containerPort: 80,  hostPort: 80,  protocol: TCP }
      - { containerPort: 443, hostPort: 443, protocol: TCP }
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
  - role: worker
    image: $K8S_NODE_IMAGE
  - role: worker
    image: $K8S_NODE_IMAGE
EOF

# ----- cluster lifecycle ----------------------------------------------------

if $REBUILD && kind get clusters | grep -qx "$CLUSTER"; then
  log "rebuild requested — deleting existing cluster"
  kind delete cluster --name "$CLUSTER"
fi

if kind get clusters | grep -qx "$CLUSTER"; then
  log "cluster '$CLUSTER' already exists, skipping create"
else
  log "creating 3-node kind cluster (this takes ~90s)"
  # No --wait flag: kindnet is disabled, so the control plane stays NotReady
  # until Calico installs in the next step. Waiting here just times out with
  # a misleading WARNING. We wait properly after CNI install.
  kind create cluster --config "$KIND_CONFIG"
fi

# kind already wrote kubeconfig to ~/.kube/config
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"

# ----- CNI: Calico ----------------------------------------------------------

if kubectl get crd installations.operator.tigera.io >/dev/null 2>&1; then
  log "Calico already installed, skipping"
else
  log "installing Calico $CALICO_VERSION (this takes ~2 min)"
  kubectl apply -f "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/tigera-operator.yaml"

  # The default Calico Installation uses a different pod CIDR than ours;
  # patch it so the CNI agrees with the cluster.
  kubectl apply -f - <<EOF
apiVersion: operator.tigera.io/v1
kind: Installation
metadata: { name: default }
spec:
  calicoNetwork:
    ipPools:
      - blockSize: 26
        cidr: 192.168.0.0/16
        encapsulation: VXLANCrossSubnet
        natOutgoing: Enabled
        nodeSelector: all()
---
apiVersion: operator.tigera.io/v1
kind: APIServer
metadata: { name: default }
spec: {}
EOF

  log "waiting for Calico to be ready (up to 3 min)"
  for i in {1..36}; do
    if kubectl -n calico-system get pods 2>/dev/null \
        | awk 'NR>1 && $3!="Running" && $3!="Completed"' | grep -q .; then
      sleep 5
    else
      # confirm calico-node is on every node
      ready=$(kubectl -n calico-system get pods -l k8s-app=calico-node --no-headers 2>/dev/null \
              | awk '$3=="Running"' | wc -l)
      if [ "$ready" -ge "3" ]; then
        log "Calico Ready ($ready calico-node pods)"
        break
      fi
      sleep 5
    fi
  done
fi

# ----- node Ready -----------------------------------------------------------

log "waiting for all nodes Ready"
kubectl wait --for=condition=Ready node --all --timeout=180s

# ----- metrics-server -------------------------------------------------------

if kubectl -n kube-system get deploy metrics-server >/dev/null 2>&1; then
  log "metrics-server already installed, skipping"
else
  log "installing metrics-server (needed for Day 3 HPA)"
  kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
  # kind uses self-signed kubelet certs; metrics-server needs --kubelet-insecure-tls
  kubectl -n kube-system patch deploy metrics-server --type=json \
    -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
  log "waiting for metrics-server to be Ready"
  kubectl -n kube-system wait --for=condition=Available deploy/metrics-server --timeout=120s || warn "metrics-server not ready; will warm up in ~60s"
fi

# ----- finalize -------------------------------------------------------------

log ""
log "============================================================"
log "cluster ready."
log ""
kubectl get nodes -o wide
log ""
log "next steps:"
log "  ./verify-cluster.sh        # run the post-bootstrap sanity check"
log "  # then move on to Lab 0 / Lab 1"
log "============================================================"
