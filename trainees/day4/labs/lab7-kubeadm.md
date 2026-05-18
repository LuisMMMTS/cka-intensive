# Lab 7 — Build a Cluster with kubeadm

**Time:** 90 min
**Goal:** bootstrap a Kubernetes cluster from scratch using `kubeadm` directly
on your Debian VM. Single-node cluster (control plane + workloads).
**This is the big one** — the exam expects you to know kubeadm cold.

> **Important shift on Day 4:** Days 1-3 used a kind cluster (Docker
> containers as nodes). For Lab 7, **we throw that away** and run kubeadm on
> your Debian VM directly. The single-node nature doesn't matter — kubeadm
> works the same; on a real cluster you'd just run `kubeadm join` on more
> machines.
>
> The trainer will walk through 7.1 together.

## 7.1 Delete the kind cluster

```sh
kind delete cluster --name cka
docker ps                       # should show no kind containers
```

Your Debian VM now has the kubeadm tooling installed but **none of the
host-level prerequisites have been configured yet**. You're going to set
them up by hand — exactly the work the CKA exam tests on the install-a-
cluster section.

## 7.2 Set up the kubeadm prerequisites

Each of these is an exam-checked item. Type them; don't copy-paste from the
slides.

### 7.2a Disable swap

kubeadm's preflight refuses to run if swap is on. Disable for the current
boot and persist across reboots:

```sh
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab
swapon --show          # should print nothing
```

### 7.2b Load kernel modules

Two modules:
- `overlay` — used by containerd's overlay filesystem
- `br_netfilter` — lets iptables see bridged traffic (needed for Calico + kube-proxy)

```sh
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter
lsmod | grep -E '^overlay|^br_netfilter'   # both should appear
```

### 7.2c Set sysctls

Three sysctls are required for Pod networking to work:

```sh
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system
# verify:
sysctl net.bridge.bridge-nf-call-iptables \
       net.bridge.bridge-nf-call-ip6tables \
       net.ipv4.ip_forward
```

### 7.2d Configure containerd's cgroup driver

kubelet defaults to the `systemd` cgroup driver. Containerd's default config
uses `cgroupfs`. Mismatch causes confusing errors. Align containerd:

```sh
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd
sudo systemctl is-active containerd     # active
```

### 7.2e Enable kubelet

The kubelet was installed by apt but isn't running yet. `kubeadm init` will
configure it and (re)start it, but enabling it now means kubelet will come
back automatically after reboots:

```sh
sudo systemctl enable kubelet
```

### 7.2f Sanity check

```sh
kubeadm version
kubelet --version
sudo crictl --runtime-endpoint unix:///run/containerd/containerd.sock version
```

If any step above failed, fix it before continuing. **These are exam
questions in disguise.**

## 7.3 What kubeadm is going to do

Five steps will happen in the next ~2 minutes when you run `kubeadm init`:

1. **Preflight checks** — swap, sysctls, kernel modules, container runtime,
   ports.
2. **Generate the cluster CA** — `/etc/kubernetes/pki/ca.{crt,key}` (10-year lifetime).
3. **Generate component certs** — apiserver, kubelet-client, etcd, etc.
4. **Write static pod manifests** — `/etc/kubernetes/manifests/`. The kubelet
   sees them and starts the control plane.
5. **Print the join command** — you don't need it (single node), but read it.

You can predict all of this. **Now type it.**

## 7.4 Init the control plane

```sh
sudo kubeadm init --pod-network-cidr=192.168.0.0/16 | tee /tmp/init.log
```

~2 minutes. Read the output carefully. The last block contains:
- A `kubectl` setup instruction
- The `kubeadm join` command (with token + cert hash)

Set up kubectl as a regular user:

```sh
mkdir -p $HOME/.kube
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

kubectl get nodes
# NAME            STATUS     ROLES           AGE   VERSION
# <vm-hostname>   NotReady   control-plane   1m    v1.36.1
```

`NotReady` is expected — no CNI yet.

## 7.5 Install Calico

```sh
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/tigera-operator.yaml
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/custom-resources.yaml

kubectl get nodes -w
# wait until status flips to Ready (~30-60s)
# Ctrl-C when it does
```

## 7.6 Untaint the control plane

Since this is a single-node cluster, you want workloads to schedule here.
Remove the `NoSchedule` taint:

```sh
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
```

(The trailing dash removes the taint.)

## 7.7 Smoke test

```sh
kubectl create deploy web --image=nginx:1.27 --replicas=2
kubectl expose deploy web --port=80
kubectl get pods -o wide          # both pods Running
kubectl run tmp --rm -it --image=busybox:1.36 --restart=Never -- wget -qO- web
```

You should see the nginx welcome HTML.

## 7.8 Inspect the PKI

The exam loves cert expiration questions:

```sh
sudo kubeadm certs check-expiration
```

Each cert with its expiration. The ones to memorize:

| Cert | Lifetime | Renewable? |
|------|----------|------------|
| `apiserver`                 | 1 year   | yes — `kubeadm certs renew apiserver` |
| `apiserver-kubelet-client`  | 1 year   | yes |
| `front-proxy-client`        | 1 year   | yes |
| `etcd/peer`, `etcd/server`  | 1 year   | yes |
| `admin.conf`                | 1 year   | yes |
| `ca.crt`                    | **10 years** | no (rebuild cluster) |

## 7.9 Stretch — upgrade plan (don't apply)

```sh
sudo kubeadm upgrade plan
```

Shows you what minor versions are available. **Don't run `apply` unless the
trainer says so** — you only have one cluster, and upgrade-then-fix is its
own can of worms.

## Deliverable

Show your trainer:

1. `kubectl get nodes -o wide` — 1 node Ready, control-plane role, v1.36.1
2. `kubectl get pods -o wide` — your nginx pods Running
3. `sudo kubeadm certs check-expiration` output

## After the lab

You have two paths for the rest of Day 4:

**Option A — Stay on the kubeadm cluster.** Labs 8 (etcd) and 8b (CRDs)
both work on single-node. Most groups do this.

**Option B — Go back to kind for multi-node.** If you want the multi-node
feel for Lab 9 (troubleshooting):

```sh
sudo kubeadm reset --force
sudo rm -rf /etc/kubernetes /var/lib/etcd $HOME/.kube/config
cd ~/cka-intensive/infra/scripts
./kind-bootstrap.sh
```

~5 minutes (kubeadm reset + kind bootstrap). The trainer will recommend
one path or the other based on time remaining.

## Why a single-node cluster is OK for the exam topics

The CKA exam *does* hand you a multi-node cluster, but the **kubeadm
mechanics** you're tested on — init, join, certs, upgrade flow — don't
care how many nodes there are. The commands are identical. You'd type the
exact same things to bring up cp-2 on a separate VM. **For knowledge transfer
to the exam, single-node kubeadm here is perfectly equivalent.**

What you DON'T get from single-node:
- Watching kubelet's join handshake from outside
- Realistic upgrade flow (drain + upgrade + uncordon, one node at a time)
- HA control-plane mechanics

Those are lecture-only on Day 4 morning anyway.
