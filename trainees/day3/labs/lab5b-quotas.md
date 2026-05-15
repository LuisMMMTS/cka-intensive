# Lab 5b — ResourceQuota & LimitRange

**Time:** 25 min
**Goal:** apply namespace-level resource governance (real CKA topic, easy points).

`k create ns lab5b && k config set-context --current --namespace=lab5b`

## 5b.1 ResourceQuota — cap the namespace

Create a quota that caps the namespace at 2 CPU, 1Gi memory, and 5 pods total.

```yaml
apiVersion: v1
kind: ResourceQuota
metadata: { name: ns-quota }
spec:
  hard:
    requests.cpu: "2"
    requests.memory: 1Gi
    limits.cpu: "4"
    limits.memory: 2Gi
    pods: "5"
```

Apply, then inspect:

```sh
k apply -f quota.yaml
k describe quota ns-quota
```

## 5b.2 Try to violate it

Create a Deployment of 6 replicas. Watch what happens:

```sh
k create deploy hog --image=nginx:1.27 --replicas=6
k get deploy,rs,pods
k describe rs -l app=hog | tail -20    # see ReplicaSet failure events
```

Expected: only 5 pods will ever run; the ReplicaSet emits `exceeded quota` events.

## 5b.3 Quota requires resource requests

Replace the hog Deployment with one that has no `resources:`. Try again:

```sh
k delete deploy hog
k create deploy hog --image=nginx:1.27 --replicas=2
k get pods
```

Expected: pods rejected with `must specify requests.cpu` (because the quota tracks `requests.cpu`).

**Lesson:** once a quota tracks a resource, every pod must declare requests/limits for that resource.

## 5b.4 LimitRange — set defaults so users don't have to

```yaml
apiVersion: v1
kind: LimitRange
metadata: { name: defaults }
spec:
  limits:
    - type: Container
      default:
        cpu: 200m
        memory: 256Mi
      defaultRequest:
        cpu: 100m
        memory: 128Mi
```

Apply, then redeploy hog with no `resources:` block. It now works because LimitRange injects the defaults.

```sh
k apply -f limitrange.yaml
k delete deploy hog
k create deploy hog --image=nginx:1.27 --replicas=2
k get pods
k describe pod <hog-pod> | grep -A4 'Limits\|Requests'
```

## Cleanup

```sh
k delete ns lab5b
```

## Deliverable

Show the trainer:
- `k describe quota ns-quota` with usage / hard side-by-side
- A pod with auto-injected requests/limits from the LimitRange
