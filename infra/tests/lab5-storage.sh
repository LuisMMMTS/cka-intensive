#!/usr/bin/env bash
# Smoke test for Lab 5 — Storage.
# Covers: StorageClass present, PVC dynamic provisioning (local-path),
# static PV manual binding via volumeName.

set -uo pipefail

LAB=lab5
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/assertions.sh
source "$SCRIPT_DIR/lib/assertions.sh"

setup_namespace lab5-smoke

# ----- 5.1 storageclass -----------------------------------------------------

if kubectl get storageclass standard >/dev/null 2>&1; then
  pass "storageclass/standard exists"
else
  fail "storageclass/standard missing — kind didn't provision local-path?"
fi

# ----- 5.2 dynamic provisioning --------------------------------------------

log "PVC + writer pod (dynamic provisioning)"
kubectl -n "$TEST_NAMESPACE" apply -f - >/dev/null <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: data }
spec:
  accessModes: [ReadWriteOnce]
  resources: { requests: { storage: 1Gi } }
  storageClassName: standard
---
apiVersion: v1
kind: Pod
metadata: { name: writer }
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: [sh, -c, "echo hello > /data/file && sleep 3600"]
      volumeMounts: [{ name: d, mountPath: /data }]
  volumes:
    - name: d
      persistentVolumeClaim: { claimName: data }
EOF

assert_pod_ready writer 60s
status=$(kubectl -n "$TEST_NAMESPACE" get pvc data -o jsonpath='{.status.phase}' 2>/dev/null)
[ "$status" = "Bound" ] && pass "PVC data Bound" || fail "PVC data status=$status (want Bound)"

if kubectl -n "$TEST_NAMESPACE" exec writer -- cat /data/file 2>/dev/null | grep -qx hello; then
  pass "writer pod read 'hello' back from PVC"
else
  fail "writer pod could NOT read expected content from PVC"
fi

# ----- 5.3 static PV with manual binding -----------------------------------

# Choose a node-local hostPath that exists on every kind worker
HOSTPATH=/tmp/lab5-static-pv
# Create directory on each node so the static PV's hostPath is valid
for node in cka-control-plane cka-worker cka-worker2; do
  docker exec "$node" mkdir -p "$HOSTPATH" 2>/dev/null || true
done

log "static PV + PVC bound by volumeName"
# Use a globally-unique PV name (PVs are cluster-scoped)
PV_NAME="lab5-static-${RANDOM}"
kubectl apply -f - >/dev/null <<EOF
apiVersion: v1
kind: PersistentVolume
metadata: { name: $PV_NAME }
spec:
  capacity: { storage: 1Gi }
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: ""
  hostPath: { path: $HOSTPATH }
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: static-data, namespace: $TEST_NAMESPACE }
spec:
  accessModes: [ReadWriteOnce]
  resources: { requests: { storage: 1Gi } }
  storageClassName: ""
  volumeName: $PV_NAME
EOF

# Wait up to 30s for binding
for i in $(seq 1 15); do
  phase=$(kubectl -n "$TEST_NAMESPACE" get pvc static-data -o jsonpath='{.status.phase}' 2>/dev/null)
  [ "$phase" = "Bound" ] && break
  sleep 2
done
[ "${phase:-}" = "Bound" ] && pass "static PVC bound to $PV_NAME" \
  || fail "static PVC never bound (phase=$phase)"

# Cleanup the cluster-scoped PV (namespace teardown won't catch it)
kubectl delete pvc static-data -n "$TEST_NAMESPACE" --wait=false >/dev/null 2>&1 || true
kubectl delete pv "$PV_NAME" --wait=false >/dev/null 2>&1 || true

finish
