#!/usr/bin/env bash
# Hard reset: delete the kind cluster and recreate it from scratch.
# ~45-90 seconds end to end.
#
# Use when:
#   - Cluster's control plane is unhealthy and you can't recover
#   - You're moving between labs that left CRDs / cluster-scoped resources
#     you don't want
#   - You ran Lab 9 troubleshooting and don't trust the recovery
#
# For routine namespace cleanup between labs, use ./lab-clean.sh instead
# (~5 seconds, doesn't touch the cluster).
#
# Usage:
#   ./kind-reset.sh           # full rebuild
#   ./kind-reset.sh --soft    # just delete user namespaces (defers to lab-clean.sh)

set -euo pipefail

CLUSTER=cka

case "${1:-}" in
  --soft) exec "$(dirname "$0")/lab-clean.sh" --all ;;
  -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
esac

log() { printf '\033[36m[reset]\033[0m %s\n' "$*"; }

log "deleting kind cluster '$CLUSTER'"
kind delete cluster --name "$CLUSTER" 2>/dev/null || true

log "rebuilding via kind-bootstrap.sh"
exec "$(dirname "$0")/kind-bootstrap.sh"
