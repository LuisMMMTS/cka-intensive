#!/usr/bin/env bash
# Bake the CKA course environment into a fresh Debian 13 VM.
# Run this ONCE on the master VM. Then snapshot the VM in dadesktop
# and replicate per trainee.
#
# Usage:
#   sudo TRAINEE_USER=trainee \
#        COURSE_REPO=https://github.com/<you>/cka-training.git \
#        ./template-bake.sh
#
# Env vars (defaults shown):
#   TRAINEE_USER=trainee        # the OS user trainees log in as
#   COURSE_REPO=<set-this>      # git URL of the course repo
#   K8S_VERSION=1.32.0          # kubeadm/kubelet/kubectl version
#   K8S_MINOR=1.32              # apt repo path
#   HELM_VERSION=v3.16.4
#   KIND_VERSION=v0.25.0
#   KINDEST_IMAGE=kindest/node:v1.32.0
#   INSTALL_VSCODE=1            # set to 0 to skip VS Code

set -euo pipefail

# ----- config ---------------------------------------------------------------

TRAINEE_USER="${TRAINEE_USER:-trainee}"
COURSE_REPO="${COURSE_REPO:?set COURSE_REPO to your git URL}"
K8S_VERSION="${K8S_VERSION:-1.32.0}"
K8S_MINOR="${K8S_MINOR:-1.32}"
HELM_VERSION="${HELM_VERSION:-v3.16.4}"
KIND_VERSION="${KIND_VERSION:-v0.25.0}"
KINDEST_IMAGE="${KINDEST_IMAGE:-kindest/node:v1.32.0}"
INSTALL_VSCODE="${INSTALL_VSCODE:-1}"

step() { printf '\n\033[36m==>\033[0m %s\n' "$*"; }

[ "$EUID" -eq 0 ] || { echo "run as root (sudo)"; exit 1; }
getent passwd "$TRAINEE_USER" >/dev/null \
  || { echo "user '$TRAINEE_USER' does not exist; create it first"; exit 1; }

# ----- 1. Base packages -----------------------------------------------------

step "installing base packages"
apt-get update
apt-get -y upgrade
apt-get -y install \
  curl ca-certificates gnupg lsb-release \
  jq git tree vim less tmux htop \
  dnsutils netcat-openbsd iproute2 procps \
  bash-completion apt-transport-https software-properties-common

# ----- 2. Docker Engine -----------------------------------------------------

step "installing Docker"
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg \
  | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/debian $(lsb_release -cs) stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin
systemctl enable --now docker
groupadd -f docker
usermod -aG docker "$TRAINEE_USER"

# ----- 3. kubectl + helm + kind --------------------------------------------

step "installing kubectl ${K8S_VERSION}"
curl -fsSLo /usr/local/bin/kubectl \
  "https://dl.k8s.io/release/v${K8S_VERSION}/bin/linux/amd64/kubectl"
chmod +x /usr/local/bin/kubectl

step "installing helm ${HELM_VERSION}"
curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz" \
  | tar -xz -C /tmp
install -m 0755 /tmp/linux-amd64/helm /usr/local/bin/helm
rm -rf /tmp/linux-amd64

step "installing kind ${KIND_VERSION}"
curl -fsSLo /usr/local/bin/kind \
  "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-amd64"
chmod +x /usr/local/bin/kind

# ----- 4. kubeadm/kubelet/kubectl for Day 4 (host-side, kubelet OFF) -------

step "installing kubeadm/kubelet/kubectl (Day 4 use only)"
mkdir -p /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${K8S_MINOR}/deb/Release.key" \
  | gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
  https://pkgs.k8s.io/core:/stable:/v${K8S_MINOR}/deb/ /" \
  > /etc/apt/sources.list.d/kubernetes.list
apt-get update
# Find the actual available package version (apt is picky about suffixes)
KUBE_PKG_VER=$(apt-cache madison kubelet | awk -v v="$K8S_VERSION" \
  '$3 ~ "^"v"-" {print $3; exit}')
[ -n "$KUBE_PKG_VER" ] || { echo "no apt version matching $K8S_VERSION found"; exit 1; }
apt-get -y install \
  kubelet="$KUBE_PKG_VER" kubeadm="$KUBE_PKG_VER" kubectl="$KUBE_PKG_VER" \
  etcd-client
apt-mark hold kubelet kubeadm kubectl

# kubelet OFF until Day 4 — kind brings its own kubelets inside its containers
systemctl disable --now kubelet

# ----- 5. kubeadm host prereqs (so Day 4 doesn't need apt mid-lab) ---------

step "kubeadm prerequisites (swap off, sysctls, kernel modules)"
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

cat >/etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

cat >/etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system >/dev/null

# containerd config — Day 4 kubeadm uses it directly
mkdir -p /etc/containerd
containerd config default >/etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd

# ----- 6. VS Code (Microsoft repo) -----------------------------------------

if [ "$INSTALL_VSCODE" = "1" ]; then
  step "installing VS Code"
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
    | gpg --dearmor --yes -o /etc/apt/keyrings/packages.microsoft.gpg
  echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] \
    https://packages.microsoft.com/repos/code stable main" \
    > /etc/apt/sources.list.d/vscode.list
  apt-get update
  apt-get -y install code

  # Pre-install useful extensions for the trainee user (no GUI required)
  step "installing VS Code extensions for $TRAINEE_USER"
  sudo -u "$TRAINEE_USER" -- bash <<EOF
set -e
for ext in \
  ms-kubernetes-tools.vscode-kubernetes-tools \
  redhat.vscode-yaml \
  ms-azuretools.vscode-docker \
  ms-vscode-remote.remote-containers \
  vscodevim.vim; do
  code --install-extension "\$ext" --force >/dev/null 2>&1 || \
    echo "(extension \$ext failed — will install on first GUI launch)"
done
EOF
fi

# ----- 7. Pre-pull lab images ----------------------------------------------

step "pre-pulling lab images"
sudo -u "$TRAINEE_USER" -- bash <<EOF
set -e
for img in $KINDEST_IMAGE \
           nginx:1.27 nginx:1.28 nginxinc/nginx-unprivileged:1.27 \
           busybox:1.36 perl:5.34 hashicorp/http-echo \
           curlimages/curl ghcr.io/rakyll/hey \
           registry.k8s.io/metrics-server/metrics-server:v0.7.2; do
  docker pull "\$img" >/dev/null 2>&1 && echo "  ✓ \$img" || echo "  ✗ \$img (will pull on demand)"
done
EOF

# ----- 8. Clone the course repo --------------------------------------------

step "cloning course repo to /opt/cka-training"
if [ -d /opt/cka-training/.git ]; then
  (cd /opt/cka-training && sudo -u "$TRAINEE_USER" git pull --ff-only)
else
  git clone "$COURSE_REPO" /opt/cka-training
fi
chown -R "$TRAINEE_USER:$TRAINEE_USER" /opt/cka-training
find /opt/cka-training/infra -name '*.sh' -exec chmod +x {} +

# ----- 9. Shell hygiene -----------------------------------------------------

step "shell hygiene for $TRAINEE_USER"
TRAINEE_HOME=$(getent passwd "$TRAINEE_USER" | cut -d: -f6)

# .bashrc additions (idempotent — only add once)
if ! grep -q '# CKA course shell setup' "$TRAINEE_HOME/.bashrc" 2>/dev/null; then
  cat >> "$TRAINEE_HOME/.bashrc" <<'EOF'

# CKA course shell setup
alias k=kubectl
source <(kubectl completion bash) 2>/dev/null
complete -F __start_kubectl k 2>/dev/null
export do='--dry-run=client -o yaml'
export now='--grace-period=0 --force'
export PATH="$PATH:/opt/cka-training/infra/scripts"
EOF
fi
chown "$TRAINEE_USER:$TRAINEE_USER" "$TRAINEE_HOME/.bashrc"

# ~/.kube directory
sudo -u "$TRAINEE_USER" mkdir -p "$TRAINEE_HOME/.kube"

# ----- 10. MOTD with the Day 1 instructions --------------------------------

cat >/etc/motd <<EOF

  ┌──────────────────────────────────────────────────────────┐
  │  CKA Intensive — your training VM                        │
  │                                                          │
  │  Course repo:    /opt/cka-training                       │
  │  Setup guide:    /opt/cka-training/trainees/vm-setup.md  │
  │                                                          │
  │  Day 1 first command:                                    │
  │      cd /opt/cka-training/infra/scripts                  │
  │      ./kind-bootstrap.sh                                 │
  │      ./verify-cluster.sh                                 │
  └──────────────────────────────────────────────────────────┘

EOF

# ----- 11. Snapshot prep ----------------------------------------------------

step "cleanup for clean snapshot"
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
truncate -s 0 /var/log/*.log 2>/dev/null || true
# Don't `docker system prune` — we want the lab images cached.

step "DONE."
echo
echo "Next steps:"
echo "  1. Test as the trainee user:"
echo "     sudo -iu $TRAINEE_USER"
echo "     /opt/cka-training/infra/scripts/verify-template.sh"
echo
echo "  2. Optionally run a full bootstrap + verify dry-run:"
echo "     sudo -iu $TRAINEE_USER"
echo "     cd /opt/cka-training/infra/scripts"
echo "     ./kind-bootstrap.sh && ./verify-cluster.sh"
echo "     kind delete cluster --name cka      # clean before snapshot"
echo
echo "  3. Snapshot this VM in dadesktop as 'master-baked'."
echo "  4. Replicate per trainee."
