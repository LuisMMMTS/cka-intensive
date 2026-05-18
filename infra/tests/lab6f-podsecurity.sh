#!/usr/bin/env bash
# Smoke test for Lab 6f — Pod Security Admission.
# Covers: label namespace with enforce=restricted, watch plain nginx
# rejected, deploy hardened spec accepted, compare with baseline.

set -uo pipefail

LAB=lab6f
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/assertions.sh
source "$SCRIPT_DIR/lib/assertions.sh"

# Use two namespaces. The default cleanup_namespace only deletes one,
# so override with a wrapper.
NS1=lab6f-restricted-$RANDOM
NS2=lab6f-baseline-$RANDOM
lab6f_cleanup() {
  kubectl delete ns "$NS1" "$NS2" --wait=false --ignore-not-found=true >/dev/null 2>&1 || true
}
trap lab6f_cleanup EXIT

# ----- 6f.1 enforce restricted on NS1 --------------------------------------

log "creating $NS1 with PSA enforce=restricted"
kubectl create ns "$NS1" >/dev/null
kubectl label ns "$NS1" \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/enforce-version=latest \
  pod-security.kubernetes.io/warn=restricted \
  pod-security.kubernetes.io/audit=restricted >/dev/null
TEST_NAMESPACE="$NS1"

# ----- 6f.2 plain nginx should be rejected ---------------------------------

log "plain nginx pod must be REJECTED by PSA restricted"
out=$(kubectl -n "$NS1" run nginx-plain --image=nginx:1.27 --restart=Never 2>&1 || true)
if echo "$out" | grep -qE 'violates PodSecurity|forbidden.*PodSecurity'; then
  pass "PSA rejected plain nginx"
else
  fail "PSA did NOT reject plain nginx (got: $(echo "$out" | head -1))"
fi
# Ensure no pod actually got created
if ! kubectl -n "$NS1" get pod nginx-plain >/dev/null 2>&1; then
  pass "no nginx-plain pod was admitted"
else
  fail "nginx-plain pod exists despite PSA enforce=restricted"
  kubectl -n "$NS1" delete pod nginx-plain --wait=false >/dev/null 2>&1
fi

# ----- 6f.3 hardened spec should be accepted ------------------------------

log "hardened nginx-unprivileged spec must be ACCEPTED"
kubectl -n "$NS1" apply -f - >/dev/null <<EOF
apiVersion: v1
kind: Pod
metadata: { name: nginx }
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 101
    seccompProfile: { type: RuntimeDefault }
  containers:
    - name: nginx
      image: nginxinc/nginx-unprivileged:1.27
      ports: [{ containerPort: 8080 }]
      securityContext:
        allowPrivilegeEscalation: false
        capabilities: { drop: [ALL] }
        readOnlyRootFilesystem: true
      volumeMounts:
        - { name: cache, mountPath: /var/cache/nginx }
        - { name: run,   mountPath: /var/run }
  volumes:
    - { name: cache, emptyDir: {} }
    - { name: run,   emptyDir: {} }
EOF
assert_pod_ready nginx 60s

# ----- 6f.4 baseline accepts plain nginx -----------------------------------

log "creating $NS2 with PSA enforce=baseline"
kubectl create ns "$NS2" >/dev/null
kubectl label ns "$NS2" pod-security.kubernetes.io/enforce=baseline >/dev/null

if kubectl -n "$NS2" run nginx --image=nginx:1.27 --restart=Never >/dev/null 2>&1; then
  pass "baseline namespace accepted plain nginx"
else
  fail "baseline namespace REJECTED plain nginx (it shouldn't)"
fi

finish
