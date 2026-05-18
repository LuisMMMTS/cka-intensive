# Lab 0 — Environment & First Cluster

**Time:** 30 min
**Goal:** bring up the 3-node Kubernetes cluster you'll use Days 1-3, talk to
it from your shell, take an anatomy tour.

> Prerequisites: you've connected to your Debian VM and confirmed Docker,
> kubectl, helm, kind all work (see `vm-setup.md`).

## 1. Pre-flight verify

```sh
docker version
kubectl version --client
helm version
kind version
```

All four must succeed. If any fail, raise your hand.

## 2. Bootstrap the cluster

The trainer will project the same command running on their machine. You run
it on yours **in parallel**.

```sh
cd ~/cka-intensive/infra/scripts
./kind-bootstrap.sh
```

What this does (≈ 2-3 min):

1. Creates a 3-node kind cluster named `cka` running Kubernetes **v1.36.1**.
2. Disables kind's default CNI (kindnet) and installs **Calico** so
   NetworkPolicy enforces (needed for Day 2 Lab 4).
3. Installs **metrics-server** with `--kubelet-insecure-tls` (needed for
   Day 3 HPA).
4. Writes the kubeconfig to `~/.kube/config` (kind does this automatically).

You'll see progress like:

```
[bootstrap] creating 3-node kind cluster (this takes ~90s)
[bootstrap] installing Calico v3.28.0 (this takes ~2 min)
[bootstrap] waiting for Calico to be ready (up to 3 min)
[bootstrap] waiting for all nodes Ready
[bootstrap] installing metrics-server (needed for Day 3 HPA)
[bootstrap] cluster ready.
```

## 3. Verify

```sh
./verify-cluster.sh
```

Should print 14 green checks. If it prints any red `✗`, read the message
above the red — it names the specific failure and usually the fix.

Manual spot-check:

```sh
kubectl get nodes -o wide
```

Expected:

```
NAME                 STATUS   ROLES           AGE    VERSION
cka-control-plane    Ready    control-plane   3m     v1.36.1
cka-worker           Ready    <none>          2m     v1.36.1
cka-worker2          Ready    <none>          2m     v1.36.1
```

```sh
kubectl get pods -A
```

All pods `Running` or `Completed`.

## 4. Confirm shell hygiene

The template sets these in `~/.bashrc` — verify they're active:

```sh
echo "$do"     # should print: --dry-run=client -o yaml
type k         # should print: k is aliased to `kubectl`
```

If either is empty, source your bashrc: `source ~/.bashrc`.

## 5. Two ways to use the cluster

You'll switch between these depending on the lab.

### A. From your Debian shell (default)

```sh
k get nodes
k create deploy demo --image=nginx:1.27 --replicas=2
k get pods
k delete deploy demo
```

This is the default for Days 1–3.

### B. `docker exec` into a node container

```sh
docker exec -it cka-control-plane bash
# now inside the cp "node"
sudo crictl ps
ls /etc/kubernetes/manifests/
exit
```

Used on Day 4 when labs touch the node directly (etcd, kubelet, static
pods).

## 6. Anatomy tour (5 min)

```sh
# from your shell
k get pods -n kube-system -o wide
k describe node cka-control-plane | head -40

# from inside the cp container
docker exec -it cka-control-plane bash
sudo crictl ps                       # the actual containers on this "node"
sudo ls /etc/kubernetes/manifests/   # static pod definitions
sudo journalctl -u kubelet -n 20 --no-pager
exit
```

Don't worry if the output looks unfamiliar — we'll dissect every piece this
week.

## Deliverable

Show your trainer:

1. `kubectl get nodes` — 3 Ready nodes at v1.36.1
2. `kubectl get pods -A` — all Running or Completed
3. `./verify-cluster.sh` exits 0 (or you've named the failing check)

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `docker info` denied | `sudo usermod -aG docker $USER && newgrp docker` or log out / back in |
| Bootstrap fails on `kind create` | Out of disk: `df -h`; out of memory: `free -h`; otherwise: `./kind-bootstrap.sh --rebuild` |
| `verify-cluster.sh` says "NetworkPolicy not enforced" | Calico didn't replace kindnet. `./kind-bootstrap.sh --rebuild` |
| `kubectl top nodes` fails | metrics-server still warming up. Retry in 60s |
| Bootstrap hangs at "waiting for Calico" | Free up RAM (close browser tabs). Re-run; idempotent |
