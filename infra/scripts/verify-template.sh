#!/usr/bin/env bash
# Verify the dadesktop Debian template is correctly baked.
# Run as the trainee user (not root) — it checks user-facing state too.
#
# Different from verify-cluster.sh: this checks the *machine*, not the *cluster*.
# Run this before kind-bootstrap.sh on first login.

set -uo pipefail

# Ensure /usr/sbin and /sbin are reachable (Debian doesn't add them to
# regular users' PATH by default — but swapon/lsmod/sysctl live there).
export PATH="/usr/local/sbin:/usr/sbin:/sbin:$PATH"

PASS=0
FAIL=0

log()  { printf '\033[36m[verify-template]\033[0m %s\n' "$*"; }
pass() { printf '  \033[32m✓\033[0m %s\n' "$*"; PASS=$((PASS+1)); }
fail() { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; FAIL=$((FAIL+1)); }

check_cmd()  {
  local cmd="$1" label="${2:-$1}"
  if command -v "$cmd" >/dev/null 2>&1; then
    pass "$label installed ($(command -v "$cmd"))"
  else
    fail "$label NOT installed"
  fi
}

check_version() {
  local cmd="$1" want="$2" actual_cmd="$3"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    fail "$cmd not installed (need v$want)"; return
  fi
  local actual
  actual=$(eval "$actual_cmd" 2>/dev/null || echo "?")
  if echo "$actual" | grep -qE "$want"; then
    pass "$cmd version contains '$want' ($actual)"
  else
    fail "$cmd version mismatch — want $want, got: $actual"
  fi
}

# ----- 1. user identity -----------------------------------------------------

log "checking user"
if [ "$EUID" -eq 0 ]; then
  fail "running as root — re-run as the trainee user (sudo -iu <user>)"
fi
WHO=$(whoami)
pass "user: $WHO"

# ----- 2. core tools --------------------------------------------------------

log "checking core tools"
for c in curl git jq tree vim less tmux htop ss ip ps systemctl journalctl; do
  check_cmd "$c"
done

# ----- 3. docker ------------------------------------------------------------

log "checking Docker"
check_cmd docker
if id -nG "$WHO" 2>/dev/null | tr ' ' '\n' | grep -qx docker; then
  pass "$WHO is in 'docker' group"
else
  fail "$WHO is NOT in 'docker' group — re-login or 'newgrp docker'"
fi
if docker info >/dev/null 2>&1; then
  pass "docker daemon reachable without sudo"
  docker_ver=$(docker version --format '{{.Server.Version}}' 2>/dev/null)
  pass "docker server version: $docker_ver"
else
  fail "cannot reach docker daemon (sudoless)"
fi

# ----- 4. k8s tooling -------------------------------------------------------

log "checking Kubernetes tooling"
check_version kubectl '1\.36\.1' 'kubectl version --client -o yaml 2>/dev/null | awk "/gitVersion/ {print \$2; exit}"'
check_version helm    'v4\.2' 'helm version --short 2>/dev/null'
check_version kind    'v0\.31' 'kind version 2>/dev/null'

# Day-4 kubeadm tooling — packages installed by the bake but NOT configured.
# The kubeadm prereqs (swap, sysctls, modules, containerd cgroup driver) are
# set up by the trainee themselves at the start of Lab 7. We only check that
# the binaries exist here.
check_version kubeadm '1\.36\.1' 'kubeadm version -o short 2>/dev/null'
check_cmd kubelet
check_cmd etcdctl    "etcdctl (etcd-client)"

# ----- 5. VS Code (optional, but expected) ---------------------------------

log "checking VS Code"
if command -v code >/dev/null 2>&1; then
  pass "code (VS Code) installed"
else
  fail "code (VS Code) NOT installed — set INSTALL_VSCODE=1 when running template-bake.sh"
fi

log "checking k9s"
if command -v k9s >/dev/null 2>&1; then
  pass "k9s installed ($(k9s version --short 2>/dev/null | head -1))"
else
  fail "k9s NOT installed"
fi

# ----- 6. repo + shell hygiene ---------------------------------------------

log "checking course repo + shell"
REPO="$HOME/cka-intensive"
if [ -d "$REPO/.git" ]; then
  pass "course repo at $REPO"
else
  fail "course repo missing at $REPO"
fi
for f in kind-bootstrap.sh kind-reset.sh lab-clean.sh verify-cluster.sh preload-images.sh; do
  if [ -x "$REPO/infra/scripts/$f" ]; then
    pass "script $f executable"
  else
    fail "script $f missing or not executable"
  fi
done

if [ -f /etc/profile.d/cka.sh ] && grep -q 'alias k=kubectl' /etc/profile.d/cka.sh 2>/dev/null; then
  pass "system-wide shell aliases at /etc/profile.d/cka.sh"
else
  fail "/etc/profile.d/cka.sh missing or incomplete"
fi
if command -v kind-bootstrap.sh >/dev/null 2>&1; then
  pass "scripts on PATH (kind-bootstrap.sh resolvable)"
else
  fail "scripts not on PATH — re-login or 'source /etc/profile.d/cka.sh'"
fi

# ----- 8. cached lab images ------------------------------------------------

log "checking pre-pulled lab images"
EXPECTED=(nginx:1.27 busybox:1.36 kindest/node:v1.36.1)
for img in "${EXPECTED[@]}"; do
  if docker image inspect "$img" >/dev/null 2>&1; then
    pass "image cached: $img"
  else
    fail "image NOT cached: $img (will pull on first use)"
  fi
done

# ----- summary --------------------------------------------------------------

echo
log "summary: $PASS passed, $FAIL failed"
if [ "$FAIL" = "0" ]; then
  log "template looks good. Next: ./kind-bootstrap.sh"
  exit 0
else
  log "template has issues — see failed checks above"
  exit 1
fi
