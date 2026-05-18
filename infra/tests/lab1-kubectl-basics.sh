#!/usr/bin/env bash
# Smoke test for Lab 1 — kubectl Mastery.
# Exercises: pod creation, deployment, scale, rollout (set image / status /
# history / undo), expose with ClusterIP.

set -uo pipefail

LAB=lab1
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/assertions.sh
source "$SCRIPT_DIR/lib/assertions.sh"

setup_namespace lab1-smoke

# 1.2 imperative pod creation
log "creating imperative pod 'nginx'"
kubectl -n "$TEST_NAMESPACE" run nginx --image=nginx:1.27 >/dev/null
assert_pod_ready nginx 60s

# 1.4 deployments + scale + rollout
log "creating deployment 'web' (3 replicas)"
kubectl -n "$TEST_NAMESPACE" create deploy web --image=nginx:1.27 --replicas=3 >/dev/null
assert_deployment_available web
assert_deployment_replicas web 3

log "scaling web → 5"
kubectl -n "$TEST_NAMESPACE" scale deploy web --replicas=5 >/dev/null
kubectl -n "$TEST_NAMESPACE" wait --for=condition=Available deploy/web --timeout=90s >/dev/null
assert_deployment_replicas web 5

log "rolling web to nginx:1.28 + verifying history"
kubectl -n "$TEST_NAMESPACE" set image deploy/web nginx=nginx:1.28 >/dev/null
kubectl -n "$TEST_NAMESPACE" rollout status deploy/web --timeout=90s >/dev/null \
  && pass "rollout to nginx:1.28 completed" \
  || fail "rollout to nginx:1.28 did not complete"

revs=$(kubectl -n "$TEST_NAMESPACE" rollout history deploy/web 2>/dev/null | grep -c '^[0-9]')
[ "$revs" -ge 2 ] && pass "rollout history has $revs revisions" || fail "rollout history has $revs (want ≥ 2)"

log "rollback deploy/web"
kubectl -n "$TEST_NAMESPACE" rollout undo deploy/web >/dev/null
kubectl -n "$TEST_NAMESPACE" rollout status deploy/web --timeout=90s >/dev/null \
  && pass "rollback completed" \
  || fail "rollback failed"

# 1.5 expose
log "exposing deploy/web"
kubectl -n "$TEST_NAMESPACE" expose deploy web --port=80 --target-port=80 >/dev/null
assert_resource_exists service web
wait_for_endpoints web

create_test_pod tmp
assert_http_from_pod_succeeds tmp "http://web.$TEST_NAMESPACE.svc.cluster.local"

finish
