#!/usr/bin/env bash
# Shared assertion library for per-lab smoke tests.
# Source from each lab test script: source "$(dirname "$0")/lib/assertions.sh"

# Caller is expected to set LAB (e.g. LAB=lab2). All output is prefixed with it.

LAB="${LAB:-unknown}"
PASS=0
FAIL=0

# ----- output helpers -------------------------------------------------------

_ts()    { date +'%H:%M:%S'; }
log()    { printf '\033[36m[%s %s]\033[0m %s\n' "$(_ts)" "$LAB" "$*"; }
pass()   { printf '  \033[32m✓\033[0m %s\n' "$*"; PASS=$((PASS+1)); }
fail()   { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; FAIL=$((FAIL+1)); }
die()    { fail "$*"; cleanup_namespace; print_summary; exit 1; }

# ----- namespace helpers ----------------------------------------------------

# Create a fresh test namespace and set it as the kubectl context default.
# All resources in this test live in this ns and are nuked at the end.
setup_namespace() {
  local ns="$1"
  log "creating namespace $ns"
  kubectl delete ns "$ns" --wait=true --ignore-not-found=true >/dev/null 2>&1 || true
  kubectl create ns "$ns" >/dev/null
  TEST_NAMESPACE="$ns"
}

cleanup_namespace() {
  [ -n "${TEST_NAMESPACE:-}" ] || return 0
  log "cleaning up namespace $TEST_NAMESPACE"
  kubectl delete ns "$TEST_NAMESPACE" --wait=false --ignore-not-found=true >/dev/null 2>&1 || true
}

# Always clean up, even on error.
trap 'cleanup_namespace' EXIT

# ----- wait helpers ---------------------------------------------------------

# Wait for a deployment to be Available, fail if it doesn't get there.
assert_deployment_available() {
  local name="$1" timeout="${2:-90s}"
  if kubectl -n "$TEST_NAMESPACE" wait --for=condition=Available "deploy/$name" --timeout="$timeout" >/dev/null 2>&1; then
    pass "deployment/$name Available"
  else
    fail "deployment/$name NOT Available within $timeout"
    kubectl -n "$TEST_NAMESPACE" describe deploy "$name" 2>/dev/null | tail -15
  fi
}

# Wait for a pod (by name) to be Ready.
assert_pod_ready() {
  local name="$1" timeout="${2:-60s}"
  if kubectl -n "$TEST_NAMESPACE" wait --for=condition=Ready "pod/$name" --timeout="$timeout" >/dev/null 2>&1; then
    pass "pod/$name Ready"
  else
    fail "pod/$name NOT Ready within $timeout"
  fi
}

# Wait for all pods matching a label to be Ready.
assert_pods_ready_by_label() {
  local label="$1" timeout="${2:-60s}"
  if kubectl -n "$TEST_NAMESPACE" wait --for=condition=Ready pod -l "$label" --timeout="$timeout" >/dev/null 2>&1; then
    pass "pods with label '$label' all Ready"
  else
    fail "pods with label '$label' NOT all Ready within $timeout"
  fi
}

# Wait for a StatefulSet to have all replicas Ready (creates pods serially,
# so a pod label-wait misses pods that haven't been created yet).
assert_statefulset_ready() {
  local name="$1" timeout="${2:-180s}"
  if kubectl -n "$TEST_NAMESPACE" rollout status "statefulset/$name" --timeout="$timeout" >/dev/null 2>&1; then
    pass "statefulset/$name fully rolled out"
  else
    fail "statefulset/$name NOT fully rolled out within $timeout"
    kubectl -n "$TEST_NAMESPACE" describe sts "$name" 2>/dev/null | tail -15
  fi
}

# Wait for a Service's Endpoints to have at least one address. Critical
# before curl-testing: kubectl expose returns immediately, but the
# endpoint controller takes a moment to populate the EndpointSlice.
wait_for_endpoints() {
  local svc="$1" timeout="${2:-30}"
  local i
  for i in $(seq 1 "$timeout"); do
    if kubectl -n "$TEST_NAMESPACE" get endpoints "$svc" \
        -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null | grep -q .; then
      return 0
    fi
    sleep 1
  done
  fail "endpoints/$svc never populated within ${timeout}s"
  return 1
}

# Wait for a Job to complete successfully.
assert_job_complete() {
  local name="$1" timeout="${2:-120s}"
  if kubectl -n "$TEST_NAMESPACE" wait --for=condition=Complete "job/$name" --timeout="$timeout" >/dev/null 2>&1; then
    pass "job/$name Complete"
  else
    fail "job/$name did NOT complete within $timeout"
  fi
}

# ----- existence / count assertions -----------------------------------------

assert_resource_exists() {
  local kind="$1" name="$2"
  if kubectl -n "$TEST_NAMESPACE" get "$kind" "$name" >/dev/null 2>&1; then
    pass "$kind/$name exists"
  else
    fail "$kind/$name does NOT exist"
  fi
}

# Assert a deployment has exactly N ready replicas.
assert_deployment_replicas() {
  local name="$1" want="$2"
  local got
  got=$(kubectl -n "$TEST_NAMESPACE" get deploy "$name" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  got="${got:-0}"
  if [ "$got" = "$want" ]; then
    pass "deployment/$name has $want ready replicas"
  else
    fail "deployment/$name has $got ready replicas (want $want)"
  fi
}

# Assert a DaemonSet has one pod ready per node.
assert_daemonset_on_every_node() {
  local name="$1"
  local desired ready
  desired=$(kubectl -n "$TEST_NAMESPACE" get ds "$name" -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null)
  ready=$(kubectl -n "$TEST_NAMESPACE" get ds "$name" -o jsonpath='{.status.numberReady}' 2>/dev/null)
  if [ -n "$desired" ] && [ "$desired" -gt 0 ] && [ "$ready" = "$desired" ]; then
    pass "daemonset/$name has $ready/$desired pods on every node"
  else
    fail "daemonset/$name has $ready ready, $desired desired"
  fi
}

# ----- HTTP / NetworkPolicy assertions --------------------------------------

# Create a long-lived test pod (busybox sleeping forever) with optional
# labels, then wait for it to be Ready AND give Calico a moment to program
# its WorkloadEndpoint. After this, kubectl exec into the pod for HTTP
# tests via assert_http_from_pod_*. Much more reliable than `kubectl run`
# per-curl: no per-pod scheduling cost, no shell quoting gymnastics, and
# the WorkloadEndpoint settle happens once.
# Usage: create_test_pod <pod-name> [pod-labels]
create_test_pod() {
  local name="$1" labels="${2:-}"
  local args=(--restart=Never --image=busybox:1.36 --command)
  [ -n "$labels" ] && args+=(--labels="$labels")
  kubectl -n "$TEST_NAMESPACE" run "$name" "${args[@]}" -- sleep 3600 >/dev/null
  if kubectl -n "$TEST_NAMESPACE" wait --for=condition=Ready "pod/$name" --timeout=30s >/dev/null 2>&1; then
    pass "test pod '$name' Ready${labels:+ (labels: $labels)}"
  else
    fail "test pod '$name' did NOT become Ready"
  fi
  # WorkloadEndpoint programming for Calico is asynchronous; pause briefly
  # so NetworkPolicy label-matching catches up. Cheap insurance.
  sleep 3
}

# HTTP GET from inside an existing pod (created via create_test_pod).
# Pass if request returns a body, fail otherwise.
assert_http_from_pod_succeeds() {
  local pod="$1" url="$2"
  if kubectl -n "$TEST_NAMESPACE" exec "$pod" -- \
      wget -qO- --timeout=8 "$url" 2>/dev/null | grep -q .; then
    pass "GET $url succeeds (from pod/$pod)"
  else
    fail "GET $url FAILED (from pod/$pod)"
  fi
}

# HTTP GET that we EXPECT to fail (NetworkPolicy denying access).
assert_http_from_pod_fails() {
  local pod="$1" url="$2"
  if kubectl -n "$TEST_NAMESPACE" exec "$pod" -- \
      wget -qO- --timeout=5 "$url" 2>/dev/null | grep -q .; then
    fail "GET $url succeeded but should have been denied (from pod/$pod)"
  else
    pass "GET $url denied (from pod/$pod)"
  fi
}

# ----- summary --------------------------------------------------------------

print_summary() {
  echo
  log "summary: $PASS pass, $FAIL fail"
  if [ "$FAIL" -eq 0 ]; then
    log "PASSED"
  else
    log "FAILED"
  fi
}

# Test scripts should call this at the end. Exits 0 on full pass, 1 otherwise.
finish() {
  print_summary
  [ "$FAIL" -eq 0 ]
}
