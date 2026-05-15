# Lab 4 — NetworkPolicy

**Time:** 45 min
**Goal:** lock down pod-to-pod traffic with NetworkPolicy.

> **Pre-req:** the kind cluster you bootstrapped on Day 1 runs **Calico**,
> which enforces NetworkPolicy. No rebuild needed. (If you'd wrecked the
> cluster, `./kind-reset.sh` first.)

`k create ns lab4 && k config set-context --current --namespace=lab4`

## 4.1 Setup

Create `frontend` and `backend` deployments + services:

```sh
k create deploy frontend --image=nginx:1.27
k create deploy backend  --image=nginx:1.27
k expose deploy frontend --port=80
k expose deploy backend  --port=80
k label deploy frontend app=frontend
k label deploy backend  app=backend
# Re-roll so labels propagate to pods (or set in YAML directly)
```

From a `tmp` pod, confirm both services are reachable:
```sh
k run tmp --rm -it --image=busybox:1.36 --restart=Never -- sh -c 'wget -qO- frontend; wget -qO- backend'
```

## 4.2 Default deny

Apply a deny-all-ingress policy to the namespace:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: default-deny }
spec:
  podSelector: {}
  policyTypes: [Ingress]
```

Re-test from `tmp`. Both should now hang/timeout.

## 4.3 Allow frontend → backend

Write a NetworkPolicy that allows pods labeled `app=frontend` to reach pods labeled `app=backend` on port 80. Apply it. Verify:

- `tmp` pod (no label) cannot reach `backend`
- A pod labeled `app=frontend` (run with `k run f --image=busybox:1.36 --labels=app=frontend ...`) CAN reach `backend`

## Deliverable

Show the trainer the test results above and your NetworkPolicy YAML.
