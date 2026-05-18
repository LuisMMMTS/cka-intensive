#!/usr/bin/env bash
# Bake the CKA course environment into a fresh Debian 13 VM.
# Run this ONCE on the master VM. Then snapshot the VM in dadesktop
# and replicate per trainee.
#
# DESIGN PRINCIPLE: this script only INSTALLS software and writes
# $TRAINEE_HOME/.bashrc + /etc/motd. It does not change kernel modules,
# sysctls, swap, fstab, locales, or display-manager configs. Anything
# that touches running-system state happens later (in lab scripts that
# trainees run themselves on Day 4).
#
# This makes the bake safe against dadesktop's image config — no risk of
# breaking auto-login, slow-boot, or display managers.
#
# WARNING: do NOT use /etc/profile.d/*.sh for shell setup on dadesktop.
# The display manager sources files there via /bin/sh (dash on Debian),
# and bash-specific syntax like `<(...)` parse-errors before any `if
# [ -n "$BASH_VERSION" ]` guard runs — which aborts session load and
# leaves the VM stuck pre-desktop. ~/.bashrc is bash-only and per-user,
# so it stays out of the display-manager path entirely.
#
# Usage:
#   sudo ./template-bake.sh

set -euo pipefail

# ----- config ---------------------------------------------------------------

COURSE_REPO="${COURSE_REPO:-https://github.com/LuisMMMTS/cka-intensive.git}"
K8S_VERSION="${K8S_VERSION:-1.36.1}"
K8S_MINOR="${K8S_MINOR:-1.36}"
KIND_VERSION="${KIND_VERSION:-v0.31.0}"
K9S_VERSION="${K9S_VERSION:-v0.32.7}"
KINDEST_IMAGE="${KINDEST_IMAGE:-kindest/node:v1.36.1}"
HELM_VERSION="${HELM_VERSION:-v4.2.0}"
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
# WARNING: apt-get upgrade has historically broken dadesktop auto-login
# (display-manager configs reset). Trainer's call — kept here because
# it's what you'd run on a real Debian install. If auto-login breaks
# again on a fresh master VM, suspect this line first.
apt-get -y upgrade
apt-get -y install \
  curl ca-certificates gnupg lsb-release \
  jq git tree vim nano less tmux htop \
  bind9-dnsutils netcat-openbsd iproute2 procps \
  bash-completion apt-transport-https \
  golang-go

# ----- 2. Docker Engine (DEB822 .sources format) ---------------------------

step "installing Docker"
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg \
  -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
cat >/etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
apt-get update
apt-get -y install docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker
groupadd -f docker
usermod -aG docker "$TRAINEE_USER"

# ----- 3. kubectl + helm + kind (binaries) ---------------------------------

step "installing kubectl ${K8S_VERSION}"
curl -fsSLo /usr/local/bin/kubectl \
  "https://dl.k8s.io/release/v${K8S_VERSION}/bin/linux/amd64/kubectl"
chmod +x /usr/local/bin/kubectl

step "installing helm ${HELM_VERSION}"
curl -fsSLo /tmp/helm.tar.gz \
  "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz"
tar -xzf /tmp/helm.tar.gz -C /tmp
install -m 0755 /tmp/linux-amd64/helm /usr/local/bin/helm
rm -rf /tmp/helm.tar.gz /tmp/linux-amd64

step "installing kind ${KIND_VERSION} (via go install)"
# Uses the just-installed golang-go to build kind from source.
# GOBIN puts the binary in /usr/local/bin (system-wide) instead of /root/go/bin.
# Modules + build cache go to /tmp/gomod (discarded after).
GOBIN=/usr/local/bin GOMODCACHE=/tmp/gomod GOCACHE=/tmp/gocache \
  go install "sigs.k8s.io/kind@${KIND_VERSION}"
rm -rf /tmp/gomod /tmp/gocache

step "installing k9s ${K9S_VERSION} (apt-tracked .deb)"
curl -fsSLo /tmp/k9s.deb \
  "https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_linux_amd64.deb"
apt-get -y install /tmp/k9s.deb
rm -f /tmp/k9s.deb

# ----- 4. kubeadm/kubelet/kubectl deb packages (DEB822 format) -------------
# We install these but do NOT configure them. Trainees set up swap/sysctls/
# kernel modules and start the kubelet themselves in Day 4 Lab 7.

step "installing kubeadm/kubelet/kubectl deb packages"
curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${K8S_MINOR}/deb/Release.key" \
  | gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg
cat >/etc/apt/sources.list.d/kubernetes.sources <<EOF
Types: deb
URIs: https://pkgs.k8s.io/core:/stable:/v${K8S_MINOR}/deb/
Suites: /
Signed-By: /etc/apt/keyrings/kubernetes-apt-keyring.gpg
EOF
apt-get update
KUBE_PKG_VER=$(apt-cache madison kubelet | awk -v v="$K8S_VERSION" \
  '$3 ~ "^"v"-" {print $3; exit}')
[ -n "$KUBE_PKG_VER" ] || die "no apt version matching $K8S_VERSION found"
apt-get -y install \
  kubelet="$KUBE_PKG_VER" kubeadm="$KUBE_PKG_VER" kubectl="$KUBE_PKG_VER" \
  etcd-client
apt-mark hold kubelet kubeadm kubectl

# ----- 5. VS Code (DEB822 format) ------------------------------------------

if [ "$INSTALL_VSCODE" = "1" ]; then
  step "installing VS Code (extensions install on first GUI launch)"
  curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
    | gpg --dearmor --yes -o /etc/apt/keyrings/packages.microsoft.gpg
  chmod 644 /etc/apt/keyrings/packages.microsoft.gpg
  cat >/etc/apt/sources.list.d/vscode.sources <<EOF
Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Components: main
Architectures: amd64,arm64,armhf
Signed-By: /etc/apt/keyrings/packages.microsoft.gpg
EOF
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

# ----- 8. Shell hygiene — per-user via ~/.bashrc --------------------------
# Idempotent: a marker block prevents double-appending on re-bake. We do
# NOT use /etc/profile.d/*.sh — see the WARNING in the header comment.

step "installing per-user shell setup in $TRAINEE_HOME/.bashrc"
BASHRC="$TRAINEE_HOME/.bashrc"
MARK_BEGIN='# ----- CKA course shell setup -----'

if [ -f "$BASHRC" ] && grep -qF "$MARK_BEGIN" "$BASHRC"; then
  echo "  ~/.bashrc already has CKA setup block, skipping"
else
  sudo -u "$TRAINEE_USER" tee -a "$BASHRC" >/dev/null <<'EOF'

# ----- CKA course shell setup -----
alias k=kubectl
export do='--dry-run=client -o yaml'
export now='--grace-period=0 --force'

# Debian doesn't put /usr/sbin and /sbin in non-root PATH by default,
# but swapoff, lsmod, sysctl, ip, ss live there (needed in Day 4 Lab 7).
case ":$PATH:" in
  *:/usr/sbin:*) ;;
  *) export PATH="$PATH:/usr/local/sbin:/usr/sbin:/sbin" ;;
esac

# Course scripts as bare commands (kind-bootstrap.sh, verify-cluster.sh, etc.)
if [ -d "$HOME/cka-intensive/infra/scripts" ]; then
  case ":$PATH:" in
    *:"$HOME/cka-intensive/infra/scripts":*) ;;
    *) export PATH="$PATH:$HOME/cka-intensive/infra/scripts" ;;
  esac
fi

# kubectl completion (safe here — .bashrc is bash-only)
if command -v kubectl >/dev/null 2>&1; then
  source <(kubectl completion bash)
  complete -F __start_kubectl k
fi
# ----- end CKA course shell setup -----
EOF
fi

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
echo "  doing anything else. Re-login is required for the docker"
echo "  group membership to take effect. The shell aliases land via"
echo "  ~/.bashrc and apply in any new bash shell."
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
