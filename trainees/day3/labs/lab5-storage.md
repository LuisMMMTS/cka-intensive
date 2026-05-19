# Lab 5 — Storage

**Time:** 45 min
**Goal:** PV, PVC, StorageClass, dynamic provisioning.

`k create ns lab5 && k config set-context --current --namespace=lab5`

## 5.1 Inspect what kind gives you

```sh
k get storageclass
k describe sc standard
```

`kind` ships with `rancher.io/local-path` — dynamic provisioner.

## 5.2 PVC + Pod (dynamic provisioning)

Create a PVC requesting 1Gi:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: data }
spec:
  accessModes: [ReadWriteOnce]
  resources: { requests: { storage: 1Gi } }
  storageClassName: standard
```

Mount it in a pod:

```yaml
apiVersion: v1
kind: Pod
metadata: { name: writer }
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "echo hello > /data/file && sleep 3600"]
      volumeMounts: [{ name: d, mountPath: /data }]
  volumes:
    - name: d
      persistentVolumeClaim: { claimName: data }
```

Verify:
```sh
k exec writer -- cat /data/file
k get pv,pvc
```

## 5.3 Static PV (manual binding)

`hostPath` PVs are node-local — fine for labs, never for production.
The PVC binds to a specific PV by name via `spec.volumeName`:

```yaml
apiVersion: v1
kind: PersistentVolume
metadata: { name: static-pv }
spec:
  capacity: { storage: 1Gi }
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: ""               # empty string = no provisioner
  hostPath: { path: /tmp/static-pv }
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: static-claim }
spec:
  accessModes: [ReadWriteOnce]
  resources: { requests: { storage: 1Gi } }
  storageClassName: ""               # must match the PV (empty here)
  volumeName: static-pv              # explicit binding
```

```sh
k apply -f static.yaml
k get pv,pvc                         # STATUS: Bound on both
```

## 5.4 Reclaim policy

Delete the PVC from 5.2. Watch what happens to the underlying PV (`kubectl get pv`). Note `Retain` vs `Delete` reclaim policies.

## Deliverable

`k get pv,pvc` showing one bound dynamically-provisioned volume and one bound static volume.
