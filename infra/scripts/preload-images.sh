#!/usr/bin/env bash
# Pre-pull lab images into each kind node's containerd cache.
# Run on the trainee's Debian VM after kind-bootstrap.sh.
# Reduces wifi pressure mid-class.
set -euo pipefail

IMAGES=(
  nginx:1.27
  nginx:1.28
  nginxinc/nginx-unprivileged:1.27
  busybox:1.36
  perl:5.34
  hashicorp/http-echo
  curlimages/curl
  ghcr.io/rakyll/hey
)

NODES=(cka-control-plane cka-worker cka-worker2)

log() { printf '\033[36m[preload]\033[0m %s\n' "$*"; }

for img in "${IMAGES[@]}"; do
  log "loading $img into kind nodes"
  # Pull on the host once, then load into each kind node
  docker pull "$img" >/dev/null
  kind load docker-image "$img" --name cka || printf '  ✗ load failed for %s\n' "$img"
done

log "done."
