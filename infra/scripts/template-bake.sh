#!/usr/bin/env bash
# Bake the CKA course environment into a fresh Debian 13 VM.
# Run this ONCE on the master VM. Then snapshot the VM in dadesktop
# and replicate per trainee.
#
# Usage:
#   sudo ./template-bake.sh
#
# The script auto-detects which user to configure (the existing non-root
# user the dadesktop VM was provisioned with). The course repo URL is
# hardcoded.
#
# Env vars (you almost never need to set these):
#   TRAINEE_USER=<auto>     # override the auto-detected user
#   COURSE_REPO=<built-in>  # override the public repo URL
#   K8S_VERSION=1.32.0      # kubeadm/kubelet/kubectl version
#   K8S_MINOR=1.32          # apt repo path
#   HELM_VERSION=v3.16.4
#   KIND_VERSION=v0.25.0
#   KINDEST_IMAGE=kindest/node:v1.32.0
#   INSTALL_VSCODE=1        # set to 0 to skip VS Code

set -euo pipefail

# ----- config ---------------------------------------------------------------

COURSE_REPO="${COURSE_REPO:-https://github.com/LuisMMMTS/cka-intensive.git}"
K8S_VERSION="${K8S_VERSION:-1.32.0}"
K8S_MINOR="${K8S_MINOR:-1.32}"
HELM_VERSION="${HELM_VERSION:-v3.16.4}"
KIND_VERSION="${KIND_VERSION:-v0.25.0}"
KINDEST_IMAGE="${KINDEST_IMAGE:-kindest/node:v1.32.0}"
INSTALL_VSCODE="${INSTALL_VSCODE:-1}"

step() { printf '\n\033[36m==>\033[0m %s\n' "$*"; }
die()  { printf '\033[31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

[ "$EUID" -eq 0 ] || die "run as root (sudo)"

# ----- 0. Auto-detect the trainee user --------------------------------------
# Priority: explicit env var > sudo invoker > first UID>=1000 in passwd
if [ -z "${TRAINEE_USER:-}" ]; then
  TRAINEE_USER="${SUDO_USER:-}"
fi
if [ -z "$TRAINEE_USER" ] || [ "$TRAINEE_USER" = "root" ]; then
  TRAINEE_USER=$(getent passwd | awk -F: '$3>=1000 && $3<65534 {print $1; exit}')
fi
[ -n "$TRAINEE_USER" ] && getent passwd "$TRAINEE_USER" >/dev/null \
  || die "could not auto-detect the trainee user. Set TRAINEE_USER=<name> and rerun."

TRAINEE_HOME=$(getent passwd "$TRAINEE_USER" | cut -d: -f6)
REPO_PATH="$TRAINEE_HOME/cka-intensive"

step "configuring for user: $TRAINEE_USER  (home: $TRAINEE_HOME)"

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
KUBE_PKG_VER=$(apt-cache madison kubelet | awk -v v="$K8S_VERSION" \
  '$3 ~ "^"v"-" {print $3; exit}')
[ -n "$KUBE_PKG_VER" ] || die "no apt version matching $K8S_VERSION found"
apt-get -y install \
  kubelet="$KUBE_PKG_VER" kubeadm="$KUBE_PKG_VER" kubectl="$KUBE_PKG_VER" \
  etcd-client
apt-mark hold kubelet kubeadm kubectl

# kubelet OFF until Day 4 — kind brings its own kubelets inside its containers
systemctl disable --now kubelet

# ----- 5. kubeadm host prereqs ---------------------------------------------

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

# ----- 6. VS Code -----------------------------------------------------------

if [ "$INSTALL_VSCODE" = "1" ]; then
  step "installing VS Code (extensions install on first GUI launch)"
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
    | gpg --dearmor --yes -o /etc/apt/keyrings/packages.microsoft.gpg
  echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] \
    https://packages.microsoft.com/repos/code stable main" \
    > /etc/apt/sources.list.d/vscode.list
  apt-get update
  apt-get -y install code
fi

# ----- 7. Pre-pull lab images (system docker cache) ------------------------

step "pre-pulling lab images"
for img in $KINDEST_IMAGE \
           nginx:1.27 nginx:1.28 nginxinc/nginx-unprivileged:1.27 \
           busybox:1.36 perl:5.34 hashicorp/http-echo \
           curlimages/curl ghcr.io/rakyll/hey \
           registry.k8s.io/metrics-server/metrics-server:v0.7.2; do
  docker pull "$img" >/dev/null 2>&1 && echo "  ✓ $img" || echo "  ✗ $img (will pull on demand)"
done

# ----- 8. Clone the course repo into the trainee's home -------------------

step "cloning course repo to $REPO_PATH"
if [ -d "$REPO_PATH/.git" ]; then
  sudo -u "$TRAINEE_USER" git -C "$REPO_PATH" pull --ff-only
else
  sudo -u "$TRAINEE_USER" git clone "$COURSE_REPO" "$REPO_PATH"
fi
find "$REPO_PATH/infra" -name '*.sh' -exec chmod +x {} +

# ----- 9. Shell hygiene — system-wide via /etc/profile.d ------------------

step "installing system-wide shell aliases (/etc/profile.d/cka.sh)"
cat >/etc/profile.d/cka.sh <<'EOF'
# CKA course shell setup — applies to every user who logs in
alias k=kubectl
if [ -n "${BASH_VERSION:-}" ]; then
  source <(kubectl completion bash) 2>/dev/null
  complete -F __start_kubectl k 2>/dev/null
fi
export do='--dry-run=client -o yaml'
export now='--grace-period=0 --force'
# Add the per-user repo's scripts/ dir to PATH if it exists
if [ -d "$HOME/cka-intensive/infra/scripts" ]; then
  export PATH="$PATH:$HOME/cka-intensive/infra/scripts"
fi
EOF
chmod 0644 /etc/profile.d/cka.sh

# ----- 10. MOTD -------------------------------------------------------------

cat >/etc/motd <<'EOF'

  ┌──────────────────────────────────────────────────────────┐
  │  CKA Intensive — your training VM                        │
  │                                                          │
  │  Course repo:    ~/cka-intensive                         │
  │  Setup guide:    ~/cka-intensive/trainees/vm-setup.md    │
  │                                                          │
  │  Day 1 first command:                                    │
  │      kind-bootstrap.sh && verify-cluster.sh              │
  │                                                          │
  │  VS Code extensions (Kubernetes, YAML, Docker, Vim)      │
  │  will install on first GUI launch.                       │
  └──────────────────────────────────────────────────────────┘

EOF

# ----- 11. Snapshot prep ---------------------------------------------------

step "cleanup for clean snapshot"
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
truncate -s 0 /var/log/*.log 2>/dev/null || true

step "DONE."
echo
echo "User configured: $TRAINEE_USER"
echo "Repo at:         $REPO_PATH"
echo
echo "Validate as $TRAINEE_USER:"
echo "  sudo -iu $TRAINEE_USER verify-template.sh"
echo
echo "Optional smoke-test before snapshot:"
echo "  sudo -iu $TRAINEE_USER bash -c 'kind-bootstrap.sh && verify-cluster.sh && kind delete cluster --name cka'"
echo
echo "Then snapshot this VM in dadesktop as 'master-baked' and replicate."
