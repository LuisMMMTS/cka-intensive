#!/usr/bin/env bash
# Smoke test for Lab 2 — Workload Types.
# Asserts that the documented Deployment / DaemonSet / StatefulSet / Job /
# CronJob examples actually work against the current cluster.

set -uo pipefail

LAB=lab2
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/assertions.sh
source "$SCRIPT_DIR/lib/assertions.sh"

setup_namespace lab2-smoke

# ----- 2.1 Deployment -------------------------------------------------------
log "creating Deployment 'web' (3 × nginx:1.27)"
kubectl -n "$TEST_NAMESPACE" create deploy web --image=nginx:1.27 --replicas=3 >/dev/null
assert_deployment_available web
assert_deployment_replicas web 3

log "rolling 'web' to nginx:1.28"
kubectl -n "$TEST_NAMESPACE" set image deploy/web nginx=nginx:1.28 >/dev/null
kubectl -n "$TEST_NAMESPACE" rollout status deploy/web --timeout=90s >/dev/null \
  && pass "rollout to nginx:1.28 completed" \
  || fail "rollout to nginx:1.28 did not complete"

# Verify the lab's rollout-history claim (≥ 2 revisions exist)
revs=$(kubectl -n "$TEST_NAMESPACE" rollout history deploy/web 2>/dev/null | grep -c '^[0-9]')
if [ "$revs" -ge 2 ]; then
  pass "rollout history has $revs revisions"
else
  fail "rollout history has only $revs revisions (want ≥ 2)"
fi

# ----- 2.2 DaemonSet --------------------------------------------------------
log "creating DaemonSet 'node-watch'"
kubectl -n "$TEST_NAMESPACE" apply -f - >/dev/null <<EOF
apiVersion: apps/v1
kind: DaemonSet
metadata: { name: node-watch }
spec:
  selector: { matchLabels: { app: node-watch } }
  template:
    metadata: { labels: { app: node-watch } }
    spec:
      containers:
        - name: nw
          image: busybox:1.36
          command: [sh, -c, "sleep 86400"]
EOF
# Give the DS a moment to schedule across nodes
sleep 5
assert_daemonset_on_every_node node-watch

# ----- 2.3 StatefulSet ------------------------------------------------------
log "creating headless Service + StatefulSet 'db'"
kubectl -n "$TEST_NAMESPACE" apply -f - >/dev/null <<EOF
apiVersion: v1
kind: Service
metadata: { name: db }
spec:
  clusterIP: None
  selector: { app: db }
  ports: [{ port: 80 }]
---
apiVersion: apps/v1
kind: StatefulSet
metadata: { name: db }
spec:
  serviceName: db
  replicas: 3
  selector: { matchLabels: { app: db } }
  template:
    metadata: { labels: { app: db } }
    spec:
      containers:
        - name: nginx
          image: nginx:1.27
          ports: [{ containerPort: 80 }]
EOF
assert_statefulset_ready db 180s
for i in 0 1 2; do assert_resource_exists pod "db-$i"; done

# Verify pod naming is stable: delete db-1, expect it to come back with the same name.
log "deleting db-1 and asserting it returns with the same name"
kubectl -n "$TEST_NAMESPACE" delete pod db-1 --wait=false >/dev/null
kubectl -n "$TEST_NAMESPACE" wait --for=condition=Ready pod/db-1 --timeout=60s >/dev/null 2>&1 \
  && pass "db-1 recreated with same name" \
  || fail "db-1 did NOT come back as db-1"

# ----- 2.4 Job + CronJob ----------------------------------------------------
log "creating Job 'pi'"
kubectl -n "$TEST_NAMESPACE" apply -f - >/dev/null <<EOF
apiVersion: batch/v1
kind: Job
metadata: { name: pi }
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: pi
          image: perl:5.34
          command: [perl, -Mbignum=bpi, -wle, 'print bpi(200)']
EOF
assert_job_complete pi 180s

log "creating CronJob 'hello'"
kubectl -n "$TEST_NAMESPACE" create cronjob hello \
  --image=busybox:1.36 --schedule="*/1 * * * *" \
  -- /bin/sh -c 'echo hello at $(date)' >/dev/null
assert_resource_exists cronjob hello

finish
