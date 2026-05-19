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

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: allow-frontend-to-backend }
spec:
  podSelector: { matchLabels: { app: backend } }   # which pods this protects
  policyTypes: [Ingress]
  ingress:
    - from:
        - podSelector: { matchLabels: { app: frontend } }
      ports:
        - protocol: TCP
          port: 80
```

Apply it (paste into a file or `cat | k apply -f -`).

Verify:

```sh
# tmp pod (no label) — still blocked, default-deny still applies:
k run tmp --rm -it --image=busybox:1.36 --restart=Never -- \
  wget -qO- --timeout=5 backend
# → connection timed out

# labeled frontend pod — allowed by the new rule:
k run f --rm -it --image=busybox:1.36 --restart=Never \
  --labels=app=frontend -- \
  wget -qO- --timeout=5 backend
# → nginx welcome page
```

## 4.4 ipBlock — allow/deny by CIDR

NetworkPolicy can also filter by source/destination IP range (handy
when the "thing on the other side" isn't a labeled pod — external load
balancer, on-prem service, the node network).

Add this policy. It lets `backend` pods receive traffic from anything
in `10.0.0.0/8` **except** `10.5.0.0/16`:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: allow-from-cidr }
spec:
  podSelector: { matchLabels: { app: backend } }
  policyTypes: [Ingress]
  ingress:
    - from:
        - ipBlock:
            cidr: 10.0.0.0/8
            except: [10.5.0.0/16]
      ports:
        - { protocol: TCP, port: 80 }
```

Note: pod-to-pod traffic inside the cluster uses **pod IPs**, which on
our kind cluster live in `192.168.0.0/16` (the Calico pod CIDR — see
the Calico Installation in `kind-bootstrap.sh`). So this 10/8 rule
wouldn't match anything in a pod-to-pod test inside our cluster.
Test concept by changing the CIDR to `192.168.0.0/16` and trying from
the `tmp` pod.

You can combine `podSelector` + `namespaceSelector` + `ipBlock` in the
same `from:` list — entries are OR'd. Inside one entry, podSelector AND
namespaceSelector together are AND'd. **This is the AND/OR trap from
the slides.**

## Deliverable

Show the trainer the test results above and your NetworkPolicy YAML.
