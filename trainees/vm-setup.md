# VM Setup — Day 1 Morning

You're working on a **Debian 13 VM** that the trainer provisioned for you. It
already has Docker, kubectl, Helm, and kind pre-installed, plus the course
repo cloned at `~/cka-intensive` (or your home directory).

Today you'll bring up a **3-node Kubernetes cluster using kind**
(Kubernetes-in-Docker). Each "node" is a Docker container with its own
kubelet, networking, and filesystem — looks identical to a real multi-node
cluster from kubectl's perspective.

```
┌──────── your Debian VM ─────────────────────────────────────┐
│                                                             │
│  kubectl / helm  ──┐                                        │
│                    │   talks to                             │
│                    ▼                                        │
│       ┌───────── cka-control-plane (Docker container) ──┐   │
│       │  apiserver, etcd, scheduler, controllers,       │   │
│       │  kubelet, containerd                            │   │
│       └─────────────────────────────────────────────────┘   │
│       ┌───── cka-worker ──────┐  ┌───── cka-worker2 ─────┐  │
│       │  kubelet, containerd  │  │  kubelet, containerd  │  │
│       └───────────────────────┘  └───────────────────────┘  │
│                                                             │
│  All three containers share Docker's bridge network.        │
│  Pods get IPs from Calico's pod CIDR (192.168.0.0/16).      │
└─────────────────────────────────────────────────────────────┘
```

---

## 1. Pre-flight check

The Debian VM should already have everything installed. Verify:

```sh
docker version
kubectl version --client    # 1.36.x
helm version                # 3.16+
kind version                # 0.25+
```

All four must succeed. If anything's missing, raise your hand — the template
was supposed to include all of it.

---

## 2. Bootstrap the cluster

The trainer will project the same command running on their machine. You run
it on yours **in parallel**.

```sh
cd ~/cka-intensive/infra/scripts     # or wherever the repo is
./kind-bootstrap.sh
```

What this does (≈ 2-3 min):

1. Creates a 3-node kind cluster named `cka` running kubeadm-installed
   Kubernetes **v1.35.1**.
2. Disables kind's default CNI (kindnet) and installs **Calico** instead, so
   NetworkPolicy actually enforces (which Day 2 Lab 4 needs).
3. Installs **metrics-server** with `--kubelet-insecure-tls` (needed for
   Day 3 HPA).
4. Writes the cluster's kubeconfig to `~/.kube/config` (kind does this
   automatically).

Watch the output. It prints `[bootstrap] ...` lines for every step. If it
errors, read the last 20 lines and ask for help.

---

## 3. Verify

```sh
./verify-cluster.sh
```

Runs 14 end-to-end checks: Docker, kind, all 3 node containers, apiserver,
nodes Ready at v1.36, `kube-system` + `calico-system` pods healthy,
metrics-server scraping, an actual test pod becoming Ready, Service+DNS+CNI
connectivity, and (critically) NetworkPolicy enforcement. Exit 0 if
everything passes.

Manual spot-check:

```sh
kubectl get nodes -o wide
```

Expected:

```
NAME                 STATUS   ROLES           AGE    VERSION
cka-control-plane    Ready    control-plane   3m     v1.35.1
cka-worker           Ready    <none>          2m     v1.35.1
cka-worker2          Ready    <none>          2m     v1.35.1
```

---

## 4. Shell hygiene

The template should have set these up in `~/.bashrc`, but verify:

```sh
alias k=kubectl
source <(kubectl completion bash)
complete -F __start_kubectl k
export do='--dry-run=client -o yaml'
export now='--grace-period=0 --force'
```

Test:

```sh
k get nodes
k explain pod.spec | head
```

---

## 5. Two ways to interact with the cluster

You'll switch between these depending on the lab.

### A. Run kubectl directly from your shell (default)

```sh
k get nodes
k create deploy demo --image=nginx:1.27 --replicas=2
k get pods
k delete deploy demo
```

This is the default for **Days 1–3** application labs. Your Debian VM has
kubectl + the kubeconfig pointing at the kind cluster. You never have to
log into any container.

### B. `docker exec` into a node container

```sh
docker exec -it cka-control-plane bash
# now you're a root shell inside the control-plane "node"
sudo crictl ps
ls /etc/kubernetes/manifests/        # the static pod manifests
journalctl -u kubelet -n 50          # kubelet logs
exit
```

You'll do this on **Day 4** when labs touch the node directly — etcd
backup, kubelet troubleshooting, static pod manifests. **For Day 4 Lab 7
specifically, you won't use kind at all** — you'll run `kubeadm` directly
on your Debian VM as a single-node cluster (we cover this on Day 4
morning).

---

## 6. Anatomy tour (5 min)

```sh
# from your shell
k get pods -n kube-system -o wide
k describe node cka-control-plane | head -40

# from inside the cp container
docker exec -it cka-control-plane bash
sudo crictl ps                           # the actual containers on this "node"
sudo ls /etc/kubernetes/manifests/       # static pod definitions
sudo cat /etc/kubernetes/manifests/kube-apiserver.yaml | head -20
exit
```

Don't worry if the output looks unfamiliar — we'll dissect every piece this
week.

---

## 7. Lifecycle commands you'll use repeatedly

| Goal | Command |
|------|---------|
| Soft cleanup (just delete user namespaces) | `./lab-clean.sh` |
| Hard reset (delete + recreate the cluster)   | `./kind-reset.sh` |
| Rebuild from scratch                         | `./kind-bootstrap.sh --rebuild` |
| Stop the cluster (keep state)                | `docker stop cka-control-plane cka-worker cka-worker2` |
| Resume                                       | `docker start cka-control-plane cka-worker cka-worker2` |

See `lab-reset.md` for which to run between each lab.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `docker info` fails with permission error | You're not in the `docker` group. `sudo usermod -aG docker $USER && newgrp docker`, or log out and back in. |
| `kind create cluster` fails on disk space | `df -h` — if the Docker overlay dir is full, `docker system prune -af`. |
| One node container stuck "Created"   | `docker logs cka-worker` for the error. Most often: kernel module missing inside the container, or cgroup driver mismatch — `./kind-reset.sh` fixes most. |
| Calico `calico-node` stuck Pending     | Free up RAM (close browser tabs); `kubectl -n calico-system describe pod -l k8s-app=calico-node`. |
| `kubectl top nodes` returns "Metrics API not available" | metrics-server takes ~60s to warm up after install. Wait. |
| Bootstrap fails midway and re-running doesn't fix it | `./kind-bootstrap.sh --rebuild` wipes the cluster and starts over. |
| `verify-cluster.sh` reports "NetworkPolicy not enforced" | The cluster came up with kindnet instead of Calico. `./kind-bootstrap.sh --rebuild` to redo. |

If you're stuck after 10 minutes, raise your hand. Don't lose Lab 0 to
setup.
