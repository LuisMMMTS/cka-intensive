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

Create a `hostPath` PV (1Gi) and a PVC that binds to it explicitly via `volumeName`. Confirm `STATUS: Bound`.

## 5.4 Reclaim policy

Delete the PVC from 5.2. Watch what happens to the underlying PV (`kubectl get pv`). Note `Retain` vs `Delete` reclaim policies.

## Deliverable

`k get pv,pvc` showing one bound dynamically-provisioned volume and one bound static volume.
