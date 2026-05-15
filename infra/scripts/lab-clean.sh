#!/usr/bin/env bash
# Soft reset between labs. ~5 seconds. Deletes only user-created namespaces and
# helm releases. Leaves kube-system, calico-system, calico-apiserver, tigera-operator,
# metrics-server, and default untouched.
#
# Use this for 90% of inter-lab transitions. Use kind-reset.sh only when:
#   - You broke the control plane (Lab 9 troubleshooting)
#   - You ran kubeadm init yourself (Lab 7)
#   - You did the etcd restore dance (Lab 8)
#   - You installed Calico the hard way and want to redo it (Lab 4 retake)
#
# Usage:
#   ./lab-clean.sh           # delete obvious lab namespaces (the common case)
#   ./lab-clean.sh --all     # also delete any namespace not in the keep-list
#   ./lab-clean.sh --dry-run # show what would be deleted

set -euo pipefail

KEEP_NAMESPACES=(
  default
  kube-system
  kube-public
  kube-node-lease
  local-path-storage     # kind's default StorageClass provisioner
  calico-system
  calico-apiserver
  tigera-operator
)

# Patterns trainees create across the labs. Add to this as new labs land.
LAB_NS_PATTERNS=(
  'lab[0-9]+b?'         # lab1, lab2, lab2b, lab3b, ...
  'q[0-9]+'             # mock exam: q1, q2, ...
  'team-[a-z]+'         # team-a (RBAC)
  'broken'              # Lab 9 troubleshooting
  'web'                 # Lab 6c (helm release ns)
  'dev'                 # Lab 6d Kustomize overlay
  'prod'                # Lab 6d Kustomize overlay
  'important'           # Lab 8 etcd state
  'lab8b'               # cert-manager mini-lab
  'cert-manager'        # if cert-manager installed by Lab 8b
  'ingress-nginx'       # if ingress-nginx installed by Lab 3
  'projectcontour'      # if Contour installed by Lab 3b
)

MODE=lab            # lab | all | dry
for arg in "$@"; do
  case "$arg" in
    --all) MODE=all ;;
    --dry-run|-n) MODE=dry ;;
    -h|--help)
      sed -n '2,18p' "$0"; exit 0 ;;
    *) echo "unknown flag: $arg" >&2; exit 1 ;;
  esac
done

log() { printf '\033[36m[clean]\033[0m %s\n' "$*"; }

# Use whatever kubeconfig is active (kind writes to ~/.kube/config by default)
KCTL=(kubectl)
"${KCTL[@]}" version --client >/dev/null 2>&1 || {
  echo "kubectl not on PATH or cluster not reachable" >&2
  exit 1
}

current_ns() { "${KCTL[@]}" get ns --no-headers -o custom-columns=:metadata.name; }

in_keeplist() {
  local ns="$1"
  for k in "${KEEP_NAMESPACES[@]}"; do
    [ "$ns" = "$k" ] && return 0
  done
  return 1
}

matches_lab_pattern() {
  local ns="$1"
  for pat in "${LAB_NS_PATTERNS[@]}"; do
    [[ "$ns" =~ ^${pat}$ ]] && return 0
  done
  return 1
}

# pass 1: uninstall helm releases in user namespaces (otherwise namespace delete is slow)
if command -v helm >/dev/null 2>&1; then
  for r in $(helm list -A -q 2>/dev/null || true); do
    NS=$(helm list -A | awk -v r="$r" '$1==r {print $2}')
    in_keeplist "$NS" && continue
    if [ "$MODE" = "dry" ]; then
      log "would helm uninstall $r in ns $NS"
    else
      log "helm uninstall $r in ns $NS"
      helm uninstall "$r" -n "$NS" >/dev/null 2>&1 || true
    fi
  done
fi

# pass 2: namespaces
TO_DELETE=()
while IFS= read -r ns; do
  in_keeplist "$ns" && continue
  if [ "$MODE" = "all" ] || matches_lab_pattern "$ns"; then
    TO_DELETE+=("$ns")
  fi
done < <(current_ns)

if [ "${#TO_DELETE[@]}" -eq 0 ]; then
  log "nothing to clean."
  exit 0
fi

for ns in "${TO_DELETE[@]}"; do
  if [ "$MODE" = "dry" ]; then
    log "would delete namespace $ns"
  else
    log "deleting namespace $ns"
    "${KCTL[@]}" delete ns "$ns" --wait=false --ignore-not-found=true
  fi
done

[ "$MODE" = "dry" ] && exit 0

# pass 3: cluster-scoped leftovers that don't go with the namespace
log "clearing cluster-scoped lab artifacts"
"${KCTL[@]}" delete clusterrolebinding -l cka-lab=true --ignore-not-found 2>/dev/null || true
"${KCTL[@]}" delete clusterrole -l cka-lab=true --ignore-not-found 2>/dev/null || true
# common explicit names trainees produce
for crb in dev-cluster-binds dev-binds-cluster node-viewer-binding; do
  "${KCTL[@]}" delete clusterrolebinding "$crb" --ignore-not-found 2>/dev/null || true
done
for cr in node-viewer; do
  "${KCTL[@]}" delete clusterrole "$cr" --ignore-not-found 2>/dev/null || true
done

# orphan PVs from Retain reclaim policy
"${KCTL[@]}" get pv --no-headers \
  -o custom-columns=:metadata.name,:status.phase 2>/dev/null \
  | awk '$2=="Released" || $2=="Available" {print $1}' \
  | while read -r pv; do
      [ -n "$pv" ] && { log "deleting orphan PV $pv"; "${KCTL[@]}" delete pv "$pv" --ignore-not-found; }
    done

log "done. Wait ~10s for namespace finalizers, then 'kubectl get ns' to confirm."
