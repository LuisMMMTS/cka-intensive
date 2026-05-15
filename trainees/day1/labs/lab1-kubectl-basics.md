# Lab 1 — kubectl Mastery

**Time:** 75 min
**Goal:** become fast with `kubectl`. Imperative-first; YAML on demand.

## Tasks

### 1.1 Contexts and namespaces

```sh
k config get-contexts
k config current-context
k create namespace lab1
k config set-context --current --namespace=lab1
k get pods               # should be empty in lab1
```

### 1.2 Imperative pod creation

Create a pod named `nginx` running `nginx:1.27`:

```sh
k run nginx --image=nginx:1.27
k get pod nginx -o wide
k logs nginx
k exec -it nginx -- bash       # exit with `exit`
```

### 1.3 Generate YAML, don't write it

```sh
k run nginx2 --image=nginx:1.27 $do > nginx2.yaml
cat nginx2.yaml
k apply -f nginx2.yaml
```

### 1.4 Deployments

```sh
k create deployment web --image=nginx:1.27 --replicas=3
k get deploy,rs,pods
k scale deploy web --replicas=5
k set image deploy/web nginx=nginx:1.28
k rollout status deploy/web
k rollout history deploy/web
k rollout undo deploy/web
```

### 1.5 Expose

```sh
k expose deploy web --port=80 --target-port=80
k get svc
k run tmp --rm -it --image=busybox:1.36 --restart=Never -- wget -qO- web
```

### 1.6 Cleanup

```sh
k delete ns lab1
```

## Stretch

- Recreate `web` from a hand-written YAML (no generator).
- Run `kubectl explain deployment.spec.strategy` and write the YAML for a `RollingUpdate` with `maxSurge: 25%, maxUnavailable: 0`.

## Deliverable

A terminal showing:
- `k rollout history deploy/web` with at least 2 revisions
- `k get svc web` reachable via `wget`
