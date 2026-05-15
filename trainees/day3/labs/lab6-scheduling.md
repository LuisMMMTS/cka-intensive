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

Write a Deployment that:
- **requiredDuringSchedulingIgnoredDuringExecution:** must run on a node with `kubernetes.io/os=linux`
- **preferredDuringSchedulingIgnoredDuringExecution:** prefers `disk=ssd`

Use `kubectl explain pod.spec.affinity.nodeAffinity` to recall the schema.

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
