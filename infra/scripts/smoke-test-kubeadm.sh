#!/usr/bin/env bash
# Automated kubeadm smoke test on the master VM.
#
# This is the Day 4 Lab 7 path — proves package versions + containerd CRI
# are compatible with `kubeadm init`. The script applies all Lab 7.2
# prereqs, runs `kubeadm init`, then FULLY reverts so the system is clean
# for snapshotting in dadesktop.
#
# It is DESTRUCTIVE while running (modifies /etc/{modules-load.d,sysctl.d,
# containerd}, edits /etc/fstab, enables kubelet). Auto-reverts on any
# failure via trap. Re-runnable — pre-cleans any prior kubeadm state.
#
# Exit codes:
#   0 — kubeadm init succeeded AND revert verified clean
#   1 — kubeadm init failed (real bug — investigate before snapshot)
#   2 — kubeadm init passed but revert incomplete (manual cleanup needed)
#
# Usage:
#   ./smoke-test-kubeadm.sh

set -uo pipefail

log()  { printf '\n\033[36m==>\033[0m %s\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; }
die()  { bad "$*"; exit 1; }

[ "$EUID" -ne 0 ] || die "do not run as root — uses sudo where needed"

# ----- 0. precondition checks -----------------------------------------------

log "precondition checks"
command -v kubeadm    >/dev/null || die "kubeadm not installed"
command -v containerd >/dev/null || die "containerd not installed"
command -v crictl     >/dev/null || die "crictl not installed — 'sudo apt-get install -y cri-tools'"
sudo -n true 2>/dev/null         || die "passwordless sudo required (or run 'sudo -v' first)"
ok "tools present, sudo cached"

# Refuse to run if a kind cluster exists — kind uses port 80/443/6443 and
# would conflict with kubeadm.
if command -v kind >/dev/null && [ -n "$(kind get clusters 2>/dev/null)" ]; then
  die "kind cluster(s) exist — 'kind delete cluster --name <name>' first"
fi

# ----- 1. capture before-state ---------------------------------------------

BEFORE=$(mktemp -d)
log "capturing before-state in $BEFORE"
sudo cp /etc/fstab "$BEFORE/fstab"
swapon --show > "$BEFORE/swap.txt" 2>/dev/null || true
ok "captured"

# ----- 2. revert function (trap + final cleanup) ---------------------------

revert() {
  log "reverting (kubeadm reset + remove configs)"
  sudo kubeadm reset --force >/dev/null 2>&1 || true
  sudo rm -rf /etc/kubernetes /var/lib/etcd
  rm -rf "$HOME/.kube"
  sudo rm -f /etc/modules-load.d/k8s.conf
  sudo rm -f /etc/sysctl.d/k8s.conf
  sudo rm -f /etc/containerd/config.toml
  sudo systemctl restart containerd >/dev/null 2>&1 || true
  sudo systemctl disable kubelet    >/dev/null 2>&1 || true
  sudo systemctl stop    kubelet    >/dev/null 2>&1 || true
  sudo cp "$BEFORE/fstab" /etc/fstab
  sudo swapon -a >/dev/null 2>&1 || true
}

# Emergency revert if we exit unexpectedly between here and step 5.
trap 'rc=$?; if [ "$rc" -ne 0 ]; then log "FAILED ($rc) — emergency revert"; revert; fi; exit $rc' EXIT

# Pre-clean: prior partial runs leave stale kubeadm state that breaks init.
sudo kubeadm reset --force >/dev/null 2>&1 || true
sudo rm -rf /etc/kubernetes /var/lib/etcd

# ----- 3. Lab 7.2 prereqs --------------------------------------------------

log "applying Lab 7.2 prereqs"

sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab

cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf >/dev/null
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter

cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf >/dev/null
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system >/dev/null

sudo containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd
sleep 2

sudo systemctl enable kubelet >/dev/null 2>&1
ok "prereqs applied"

# Verify CRI is reachable before kubeadm tries it
if ! sudo crictl --runtime-endpoint unix:///run/containerd/containerd.sock version >/dev/null 2>&1; then
  die "CRI plugin not responding after containerd restart — investigate /etc/containerd/config.toml"
fi
ok "CRI reachable"

# ----- 4. kubeadm init ------------------------------------------------------

log "running kubeadm init (~2 min — proves package + CRI versions work)"
if sudo kubeadm init --pod-network-cidr=192.168.0.0/16 >/tmp/kubeadm-init.log 2>&1; then
  ok "kubeadm init succeeded"
  tail -5 /tmp/kubeadm-init.log
else
  bad "kubeadm init FAILED — see /tmp/kubeadm-init.log"
  tail -30 /tmp/kubeadm-init.log
  # trap will revert + exit non-zero
  exit 1
fi

# ----- 5. clean revert ------------------------------------------------------

trap - EXIT          # disable trap; we'll do the clean revert ourselves
revert

# ----- 6. verify clean state ------------------------------------------------

log "verifying revert was clean"
PASS=0
FAIL=0
check() {
  if eval "$1" >/dev/null 2>&1; then
    ok "$2"; PASS=$((PASS+1))
  else
    bad "$2"; FAIL=$((FAIL+1))
  fi
}

check '! test -e /etc/kubernetes'              '/etc/kubernetes removed'
check '! test -e /var/lib/etcd'                '/var/lib/etcd removed'
check '! test -f /etc/modules-load.d/k8s.conf' '/etc/modules-load.d/k8s.conf removed'
check '! test -f /etc/sysctl.d/k8s.conf'       '/etc/sysctl.d/k8s.conf removed'
check '! test -f /etc/containerd/config.toml'  '/etc/containerd/config.toml removed'
check '[ "$(systemctl is-enabled kubelet 2>/dev/null)" != enabled ]' 'kubelet disabled'
check 'diff -q /etc/fstab "$BEFORE/fstab"'     '/etc/fstab matches original'

echo
if [ "$FAIL" -eq 0 ]; then
  rm -rf "$BEFORE" /tmp/kubeadm-init.log
  log "SMOKE TEST PASSED — kubeadm path works, system clean for snapshot"
  exit 0
else
  log "smoke test passed but $FAIL revert checks failed"
  log "before-state preserved at $BEFORE — fix manually before snapshotting"
  exit 2
fi
