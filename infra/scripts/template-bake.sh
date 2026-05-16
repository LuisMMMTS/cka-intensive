#!/usr/bin/env bash
# Bake the CKA course environment into a fresh Debian 13 VM.
# Run this ONCE on the master VM. Then snapshot the VM in dadesktop
# and replicate per trainee.
#
# DESIGN PRINCIPLE: this script only INSTALLS software and writes
# /etc/profile.d/cka.sh + /etc/motd. It does not change kernel modules,
# sysctls, swap, fstab, locales, or display-manager configs. Anything
# that touches running-system state happens later (in lab scripts that
# trainees run themselves on Day 4).
#
# This makes the bake safe against dadesktop's image config — no risk of
# breaking auto-login, slow-boot, or display managers.
#
# Usage:
#   sudo ./template-bake.sh

set -euo pipefail

# ----- config ---------------------------------------------------------------

COURSE_REPO="${COURSE_REPO:-https://github.com/LuisMMMTS/cka-intensive.git}"
K8S_VERSION="${K8S_VERSION:-1.32.0}"
K8S_MINOR="${K8S_MINOR:-1.32}"
HELM_VERSION="${HELM_VERSION:-v3.16.4}"
KIND_VERSION="${KIND_VERSION:-v0.25.0}"
K9S_VERSION="${K9S_VERSION:-v0.32.7}"
KINDEST_IMAGE="${KINDEST_IMAGE:-kindest/node:v1.32.0}"
INSTALL_VSCODE="${INSTALL_VSCODE:-1}"

step() { printf '\n\033[36m==>\033[0m %s\n' "$*"; }
die()  { printf '\033[31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

[ "$EUID" -eq 0 ] || die "run as root (sudo)"

# ----- 0. Auto-detect the trainee user --------------------------------------

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

# ----- 1. Base packages (install-only; no apt-get upgrade) -----------------

step "installing base packages"
apt-get update
apt-get -y install \
  curl ca-certificates gnupg lsb-release \
  jq git tree vim less tmux htop \
  bind9-dnsutils netcat-openbsd iproute2 procps \
  bash-completion apt-transport-https

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

# ----- 3. kubectl + helm + kind + k9s (binaries) ---------------------------

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

step "installing k9s ${K9S_VERSION}"
curl -fsSL "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_amd64.tar.gz" \
  | tar -xz -C /tmp k9s
install -m 0755 /tmp/k9s /usr/local/bin/k9s
rm -f /tmp/k9s

# ----- 4. kubeadm/kubelet/kubectl deb packages (for Day 4) -----------------
# We install these but do NOT configure them. Trainees set up swap/sysctls/
# kernel modules and start the kubelet themselves in Day 4 Lab 7.

step "installing kubeadm/kubelet/kubectl deb packages"
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

# ----- 5. VS Code -----------------------------------------------------------

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

# ----- 6. Pre-pull lab images (system docker cache) ------------------------

step "pre-pulling lab images"
for img in $KINDEST_IMAGE \
           nginx:1.27 nginx:1.28 nginxinc/nginx-unprivileged:1.27 \
           busybox:1.36 perl:5.34 hashicorp/http-echo \
           curlimages/curl \
           registry.k8s.io/metrics-server/metrics-server:v0.7.2; do
  docker pull "$img" >/dev/null 2>&1 && echo "  + $img" || echo "  - $img (will pull on demand)"
done

# ----- 7. Clone the course repo into the trainee's home -------------------

step "cloning course repo to $REPO_PATH"
if [ -d "$REPO_PATH/.git" ]; then
  sudo -u "$TRAINEE_USER" git -C "$REPO_PATH" pull --ff-only
else
  sudo -u "$TRAINEE_USER" git clone "$COURSE_REPO" "$REPO_PATH"
fi
find "$REPO_PATH/infra" -name '*.sh' -exec chmod +x {} +

# ----- 8. Shell hygiene — system-wide via /etc/profile.d ------------------

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
# Debian doesn't put /usr/sbin and /sbin in non-root PATH by default,
# but swapon, lsmod, sysctl, ip, ss live there.
case ":$PATH:" in
  *:/usr/sbin:*) ;;
  *) export PATH="$PATH:/usr/local/sbin:/usr/sbin:/sbin" ;;
esac
# Add the per-user repo's scripts/ dir to PATH if it exists
if [ -d "$HOME/cka-intensive/infra/scripts" ]; then
  export PATH="$PATH:$HOME/cka-intensive/infra/scripts"
fi
EOF
chmod 0644 /etc/profile.d/cka.sh

# ----- 9. MOTD --------------------------------------------------------------

cat >/etc/motd <<'EOF'

  ┌──────────────────────────────────────────────────────────┐
  │  CKA Intensive — your training VM                        │
  │                                                          │
  │  Course repo:    ~/cka-intensive                         │
  │  Setup guide:    ~/cka-intensive/trainees/vm-setup.md    │
  │                                                          │
  │  Day 1 first command:                                    │
  │      kind-bootstrap.sh && verify-cluster.sh              │
  └──────────────────────────────────────────────────────────┘

EOF

step "DONE."
echo
echo "  User configured: $TRAINEE_USER"
echo "  Repo at:         $REPO_PATH"
echo
echo "═══════════════════════════════════════════════════════════════"
echo "  IMPORTANT: log out and back in as $TRAINEE_USER before"
echo "  doing anything else. The docker group membership and the"
echo "  shell aliases only take effect in a fresh login session."
echo "═══════════════════════════════════════════════════════════════"
echo
echo "  After re-login, validate:"
echo "      verify-template.sh"
echo
echo "  What this bake does NOT do (Lab 7 covers it on Day 4):"
echo "    - swap off / fstab edit"
echo "    - kernel modules (overlay, br_netfilter)"
echo "    - kubeadm sysctls (bridge-nf-call-*, ip_forward)"
echo "    - containerd cgroup driver = systemd"
echo "    - kubelet enable/start"
echo "  Trainees set these up themselves at the start of Lab 7."
echo
echo "  Smoke-test the kind path (Days 1-3) now:"
echo "      kind-bootstrap.sh && verify-cluster.sh && kind delete cluster --name cka"
echo
echo "  Then snapshot this VM in dadesktop as 'master-baked' and replicate."
