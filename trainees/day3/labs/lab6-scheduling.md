# Lab 6 — Scheduling

**Time:** 45 min
**Goal:** taints, tolerations, nodeSelector, nodeAffinity, resources.

`k create ns lab6 && k config set-context --current --namespace=lab6`

## 6.1 nodeSelector

Label a worker node:
```sh
k label node cka-worker disk=ssd
```

Create a pod with `nodeSelector: { disk: ssd }` and confirm it lands on `cka-worker` only.

## 6.2 Taints & tolerations

Taint the same node:
```sh
k taint node cka-worker dedicated=db:NoSchedule
```

Try to deploy a Deployment of 5 replicas with no toleration — they should avoid `cka-worker`. Then add a toleration matching `dedicated=db:NoSchedule` and watch them schedule there.

## 6.3 nodeAffinity (preferred vs required)

On the exam you regenerate this schema with `kubectl explain
pod.spec.affinity.nodeAffinity` — do that at least once to learn the shape.

Starter Deployment:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata: { name: affinity-demo }
spec:
  replicas: 3
  selector: { matchLabels: { app: affinity-demo } }
  template:
    metadata: { labels: { app: affinity-demo } }
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                  - key: kubernetes.io/os
                    operator: In
                    values: [linux]
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 50
              preference:
                matchExpressions:
                  - key: disk
                    operator: In
                    values: [ssd]
      containers:
        - { name: nginx, image: nginx:1.27 }
```

```sh
k apply -f affinity.yaml
k get pods -l app=affinity-demo -o wide       # prefers the disk=ssd node
```

**Required** is a hard filter — pods stay Pending if no node matches.
**Preferred** is a soft scoring nudge — scheduler still picks something
even if no node has the label.

## 6.4 Resource requests & limits

Create a Deployment with:
- requests: cpu 100m, memory 128Mi
- limits:   cpu 500m, memory 256Mi

Confirm with `k describe pod`. Then deliberately request 100Gi memory and observe the pod stuck `Pending` with reason `Insufficient memory` in events.

## Cleanup taints/labels

```sh
k taint node cka-worker dedicated-    # trailing dash removes
k label node cka-worker disk-
```

## Deliverable

Show the pending pod from 6.4 and the events from `k describe pod` explaining why.
