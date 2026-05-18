#!/usr/bin/env bash
# Final pre-snapshot check on the master VM. Run after verify-template.sh
# and (optionally) smoke-test-kubeadm.sh, immediately before powering off
# to snapshot in dadesktop.
#
# Confirms three things:
#   1. No live cluster state (kind / kubeadm) — would carry into replicas
#   2. No host config drift from the bake (Lab 7 files reverted, fstab intact)
#   3. Bake state intact (~/.bashrc, pre-pulled images)
#
# Exit 0 = ready to snapshot. Exit 1 = items need attention.

set -uo pipefail

PASS=0; FAIL=0; WARN=0
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; PASS=$((PASS+1)); }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; FAIL=$((FAIL+1)); }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; WARN=$((WARN+1)); }
log()  { printf '\n\033[36m==>\033[0m %s\n' "$*"; }

# ----- 1. no live clusters --------------------------------------------------

log "no live cluster state"

if command -v kind >/dev/null 2>&1; then
  clusters=$(kind get clusters 2>/dev/null | tr '\n' ' ')
  if [ -z "$clusters" ]; then
    ok "no kind clusters"
  else
    bad "kind clusters still exist: $clusters"
  fi
else
  warn "kind not installed (unexpected)"
fi

if command -v docker >/dev/null 2>&1; then
  running=$(docker ps -q 2>/dev/null | wc -l | tr -d ' ')
  if [ "$running" = 0 ]; then
    ok "no docker containers running"
  else
    bad "$running docker container(s) running"
  fi
fi

# ----- 2. no kubeadm / Lab 7 leftovers --------------------------------------

log "no Lab 7 host-config leftovers"

for f in /etc/kubernetes /var/lib/etcd \
         /etc/modules-load.d/k8s.conf /etc/sysctl.d/k8s.conf \
         /etc/containerd/config.toml; do
  if [ ! -e "$f" ]; then
    ok "$f absent"
  else
    bad "$f present — Lab 7 prereqs not fully reverted"
  fi
done

if [ "$(systemctl is-enabled kubelet 2>/dev/null)" = enabled ]; then
  bad "kubelet is enabled (Lab 7 enables it — must be disabled in snapshot)"
else
  ok "kubelet disabled"
fi

# fstab — Lab 7 comments out the swap line. The original VM may or may not
# have had a swap line, but in either case it should not be present as a
# commented-out one. (If the original had no swap, no '#... swap ...' line
# should exist. If the original had swap, it should be uncommented.)
if grep -qE '^\s*#[^a-zA-Z0-9_-]*[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+swap\b' /etc/fstab; then
  bad "/etc/fstab has a commented-out swap line (Lab 7 edit not reverted)"
else
  ok "/etc/fstab swap line untouched"
fi

# ----- 3. bake state intact -------------------------------------------------

log "bake state intact"

if [ -f "$HOME/.bashrc" ] && grep -q 'alias k=kubectl' "$HOME/.bashrc"; then
  ok "~/.bashrc has CKA setup block"
else
  bad "~/.bashrc missing CKA setup — re-run template-bake.sh"
fi

EXPECTED_IMAGES=(nginx:1.27 busybox:1.36 kindest/node:v1.35.1 \
                 registry.k8s.io/metrics-server/metrics-server:v0.7.2)
for img in "${EXPECTED_IMAGES[@]}"; do
  if docker image inspect "$img" >/dev/null 2>&1; then
    ok "image cached: $img"
  else
    bad "image NOT cached: $img — preload-images.sh or template-bake.sh step 6"
  fi
done

# ----- 4. cleanup hygiene (warnings only) ----------------------------------

log "cleanup hygiene"

hist=$(wc -l < "$HOME/.bash_history" 2>/dev/null || echo 0)
if [ "$hist" -lt 10 ]; then
  ok "bash history small ($hist lines)"
else
  warn "bash history has $hist entries — 'cat /dev/null > ~/.bash_history && history -c'"
fi

if [ -d /var/cache/apt/archives ] && [ "$(du -sm /var/cache/apt/archives 2>/dev/null | awk '{print $1}')" -gt 100 ]; then
  warn "apt cache > 100 MB — 'sudo apt-get clean' shrinks the snapshot"
else
  ok "apt cache small"
fi

# ----- summary --------------------------------------------------------------

echo
log "summary: $PASS pass, $FAIL fail, $WARN warn"
echo
if [ "$FAIL" -eq 0 ]; then
  log "READY TO SNAPSHOT. Power off the VM in dadesktop, take the snapshot,"
  log "tag it (e.g. cka-master-v1), then replicate per trainee."
  exit 0
else
  log "NOT READY — fix the $FAIL failed checks above before snapshotting"
  exit 1
fi
