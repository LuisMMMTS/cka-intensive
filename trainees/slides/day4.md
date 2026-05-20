---
marp: true
theme: default
paginate: true
size: 16:9
header: "CKA Intensive — Day 4"
footer: "© Luis Torres"
style: |
  section { font-size: 24px; }
  pre, code { background: #1e1e1e; color: #eee; }
  h1 { color: #326ce5; }
  h2 { color: #326ce5; border-bottom: 2px solid #326ce5; }
  table { font-size: 22px; }
---

# CKA Intensive
## Day 4 — Cluster Lifecycle, CRDs, Troubleshooting, Mock Exam

Today's cluster: kubeadm on Kubernetes **v1.36.1** (you'll build it in Lab 7)

The exam-prep day. We build a cluster, recover from disasters, learn the troubleshooting playbook, then sit a mock.

---

## Today

1. **Morning quiz** (10 min, oral)
2. kubeadm — bootstrap, join, upgrade, HA topologies
3. **TLS cert management** — what expires, when, how to rotate
4. **Lab 7** — build a cluster with kubeadm directly on the Debian VM
5. etcd backup & restore
6. **Lab 8** — etcd
7. **CRDs and operators** overview
8. **Lab 8b** — install an operator, observe reconciliation
9. Troubleshooting playbook + logging + metrics
10. **Lab 9** — broken cluster (random scenario)
11. **Mock Exam — 75 min, no notes, no Google, no AI**
12. Mock review, exam-day strategy, wrap-up

---

## kubeadm — what it does, what it doesn't

**Does:**
- Generates the PKI (`/etc/kubernetes/pki/`)
- Writes static pod manifests for apiserver, scheduler, controller-manager, etcd (`/etc/kubernetes/manifests/`)
- Bootstraps the kubelet via the kubelet-config ConfigMap
- Issues join tokens so workers can register
- Manages upgrades

**Does NOT:**
- Install a CNI (you do)
- Install monitoring/logging
- Install a CSI/cloud-controller
- Manage cluster lifecycle beyond install/upgrade (no scaling, no recovery)

It's a **bootstrapper**, not a lifecycle tool.

---

## Pre-flight (every node, every time)

```sh
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab             # persist

sudo modprobe overlay
sudo modprobe br_netfilter

cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system
```

Then install: **containerd** + kubelet + kubeadm + kubectl, all matching the target version.

---

## containerd — the runtime

```sh
sudo apt-get install -y containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
# critical: set SystemdCgroup = true so the cgroup driver matches kubelet
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd
```

If you forget `SystemdCgroup = true`, kubelet and containerd will fight over cgroups → flapping nodes. This is the #1 kubeadm install bug.

---

## Install kubelet, kubeadm, kubectl (v1.36)

```sh
sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.36/deb/Release.key | \
  sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
https://pkgs.k8s.io/core:/stable:/v1.36/deb/ /" | \
  sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl              # pin
```

The repo URL is **versioned** per minor. To upgrade to 1.33, change the URL.

---

## kubeadm init (control plane)

```sh
sudo kubeadm init \
  --pod-network-cidr=192.168.0.0/16 \                 # Calico default
  --apiserver-advertise-address=$(hostname -i) \
  --upload-certs

# save the join command from the output, e.g.:
# kubeadm join 10.0.0.5:6443 --token <t> \
#   --discovery-token-ca-cert-hash sha256:<h>

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

You can regenerate the join command anytime:

```sh
kubeadm token create --print-join-command
```

---

## Install a CNI

`k get nodes` shows `NotReady` until a CNI is in place. Calico:

```sh
k apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/tigera-operator.yaml
k apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/custom-resources.yaml

k get pods -A -w                # wait for calico-system to come up
k get nodes                     # control plane → Ready
```

The pod CIDR in `custom-resources.yaml` (default `192.168.0.0/16`) **must match** `--pod-network-cidr` from `kubeadm init`.

---

## Join workers

On each worker (after pre-flight + containerd + kubeadm install):

```sh
sudo kubeadm join 10.0.0.5:6443 --token <t> \
  --discovery-token-ca-cert-hash sha256:<h>
```

On control plane:

```sh
k get nodes
# NAME    STATUS   ROLES           AGE   VERSION
# cp-1    Ready    control-plane   5m    v1.36.1
# w-1     Ready    <none>          1m    v1.36.1
```

To set worker role label cosmetically:
```sh
k label node w-1 node-role.kubernetes.io/worker=
```

---

## Control plane HA — two topologies

**Stacked etcd** (kubeadm default):

```
┌──cp-1──┐   ┌──cp-2──┐   ┌──cp-3──┐
│apiserver│  │apiserver│  │apiserver│
│ etcd    │  │ etcd    │  │ etcd    │   ← etcd colocated with cp
└─────────┘  └─────────┘  └─────────┘
        │         │            │
        ▼         ▼            ▼
        [   LB on :6443    ]
```

**External etcd**:

```
┌──cp-1──┐   ┌──cp-2──┐         ┌─etcd-1─┐
│apiserver│  │apiserver│ ────►  │ etcd-2 │
└─────────┘  └─────────┘        │ etcd-3 │
                                 └────────┘
```

Stacked: simpler, fewer machines.
External: stronger blast-radius isolation, harder ops, recommended for very large clusters.

Both need an **L4 load balancer** in front of `apiserver:6443`.

---

## HA init flow

```sh
# init the first control plane with --control-plane-endpoint pointing at the LB
sudo kubeadm init \
  --control-plane-endpoint=cluster.example.com:6443 \
  --upload-certs \
  --pod-network-cidr=192.168.0.0/16

# join the other CPs
sudo kubeadm join cluster.example.com:6443 \
  --token <t> --discovery-token-ca-cert-hash sha256:<h> \
  --control-plane --certificate-key <k>
```

`--upload-certs` puts the cluster's certs into a kubeadm-managed Secret so other CPs can pull them. The `--certificate-key` is printed once at init time; print again with `kubeadm init phase upload-certs --upload-certs`.

---

## kubeadm upgrade flow (memorize this)

```sh
# CONTROL PLANE (one CP at a time in HA)
k drain <cp> --ignore-daemonsets
sudo apt-get update
sudo apt-get install -y kubeadm=1.36.x-*
sudo kubeadm upgrade plan
sudo kubeadm upgrade apply v1.36.x
# (on additional CPs: `kubeadm upgrade node` instead of `apply`)

sudo apt-get install -y kubelet=1.36.x-* kubectl=1.36.x-*
sudo systemctl daemon-reload && sudo systemctl restart kubelet
k uncordon <cp>

# WORKERS (one at a time)
k drain <w> --ignore-daemonsets
# on worker:
sudo apt-get install -y kubeadm=1.36.x-*
sudo kubeadm upgrade node
sudo apt-get install -y kubelet=1.36.x-* kubectl=1.36.x-*
sudo systemctl daemon-reload && sudo systemctl restart kubelet
k uncordon <w>
```

Rule: **never skip minor versions** (1.30 → 1.32 in one shot is not supported). Always 1.30 → 1.31 → 1.32.

---

## TLS certificate management

kubeadm generates these certs under `/etc/kubernetes/pki/`:

| Cert | What it's for | Default expiry |
|---|---|---|
| `apiserver.crt` | apiserver TLS | 1 year |
| `apiserver-kubelet-client.crt` | apiserver → kubelet | 1 year |
| `front-proxy-client.crt` | aggregation layer | 1 year |
| `etcd/server.crt`, `peer.crt`, `healthcheck-client.crt` | etcd | 1 year |
| `ca.crt`, `etcd/ca.crt`, `front-proxy-ca.crt` | CAs | **10 years** |
| Kubeconfigs (`admin.conf`, `controller-manager.conf`, `scheduler.conf`, `kubelet.conf`) | client certs embedded | 1 year |

**Implication:** if you don't `kubeadm upgrade` for a year, certs expire and the cluster falls over.

---

## Check + renew certs

```sh
sudo kubeadm certs check-expiration

#  CERTIFICATE                EXPIRES                 RESIDUAL TIME   ...
#  admin.conf                 Mar 02, 2026 14:13 UTC  300d            ...
#  apiserver                  Mar 02, 2026 14:13 UTC  300d            ...
#  ...
```

Renew all at once:

```sh
sudo kubeadm certs renew all
sudo systemctl restart kubelet                            # reload kube-apiserver static pod
```

Renew one:

```sh
sudo kubeadm certs renew apiserver
```

`kubeadm upgrade` **also** renews certs as a side-effect. That's the recommended path.

---

## Kubelet client cert auto-rotation

kubelet rotates its own client cert if enabled:

```yaml
# /var/lib/kubelet/config.yaml
rotateCertificates: true
serverTLSBootstrap: true
```

The kubelet renews via the CSR API. Pending CSRs need approval (auto-approved by the `csrapproving` controller if its RBAC is in place).

```sh
k get csr
k certificate approve <csr-name>
```

---

## Rotate the cluster CA (rare, painful)

If the CA itself is compromised, you must:

1. Generate a new CA
2. Re-issue every certificate signed by it
3. Distribute the new CA to every kubelet, every kubeconfig, every controller
4. Update every TLS Secret / Webhook config

kubeadm has limited support for this. In practice: rebuild the cluster. Plan for **before** you hit year 10.

---

# Lab 7 — kubeadm

→ `trainees/day4/labs/lab7-kubeadm.md`

**60 min.**
- Snapshot-restore to `kubeadm-ready` state (pre-init Multipass VMs)
- Run `kubeadm init` directly on your Debian VM
- Install Calico, get to Ready
- (Single-node — no joins needed; untaint control plane to schedule workloads)
- `kubeadm certs check-expiration` to inspect the PKI
- (Stretch) `kubeadm upgrade plan` dry-run

---

# Edge & Lightweight Kubernetes

The other 90% of clusters in the wild.

---

## Why this matters

You will learn `kubeadm`. It's what the exam tests. It's also **not what most production clusters use**.

| Where | What runs |
|-------|-----------|
| AWS EKS / GKE / AKS    | A managed flavor (not user-visible) |
| Bare-metal datacenters | kubeadm or distro-specific (Rancher, OpenShift) |
| **Edge / IoT / branch offices** | **k3s, k0s, MicroK8s** |
| CI runners / dev      | kind, k3s, MicroK8s |

When the constraint is **"this cluster runs on a Raspberry Pi 4 with 8 GB RAM,"** kubeadm is the wrong answer. You reach for k3s.

---

## k3s — the lightweight default

Built by Rancher (now SUSE). **One binary. ~50 MB. SQLite or embedded etcd. ARM-friendly.**

```sh
# install a single-node k3s cluster in 30 seconds:
curl -sfL https://get.k3s.io | sh -
sudo k3s kubectl get nodes
```

What it cuts vs vanilla:
- **No external etcd by default** — uses SQLite for state (or embedded etcd if HA)
- **Bundled networking** (Flannel by default) + **Traefik ingress** + **local-path storage**
- **Removes cloud-controller, legacy storage plugins, alpha features**

What it keeps: the **full Kubernetes API**. `kubectl` doesn't know the difference.

Used by: Rio Tinto mining trucks, John Deere combines, Costco POS terminals.

---

## k0s — vendor-neutral, embedded etcd

By Mirantis. Similar pitch to k3s but:
- **Embedded etcd** instead of SQLite — proper distributed quorum from 1 node up
- **No CNI/CSI/ingress pre-installed** — you pick
- Single binary, no system services, no host modifications

```sh
curl -sSLf https://get.k0s.sh | sudo sh
sudo k0s install controller --single
sudo k0s start
sudo k0s kubectl get nodes
```

Used by: appliance vendors, Mirantis customers, anyone uncomfortable with k3s's bundled-everything approach.

---

## MicroK8s — Ubuntu's flavor

By Canonical, packaged as a **snap**.

```sh
sudo snap install microk8s --classic
microk8s status --wait-ready
microk8s kubectl get nodes
microk8s enable dns ingress storage   # opt in to features
```

Strengths:
- Trivial install on Ubuntu / WSL
- Add-on system (`microk8s enable <thing>`) for common features
- Easy cluster join (`microk8s add-node`)

Used by: Ubuntu shops, dev environments, education.

---

## When to pick which

```
Single dev laptop, instant cluster?            kind  or  MicroK8s
Edge device, ARM, 2 GB RAM?                    k3s
Appliance OEM, single-binary embedded?         k0s
On-prem datacenter, full Kubernetes?           kubeadm
Managed cloud?                                 EKS / GKE / AKS
HA on bare-metal with vendor support?          OpenShift, Rancher, kubeadm + Cilium
```

**For the exam: you need kubeadm cold.** The others are for your career after.

---

## Tuning the kubelet for constrained hardware

```yaml
# /var/lib/kubelet/config.yaml (KubeletConfiguration)
kubeReserved:
  cpu: "100m"
  memory: "200Mi"      # what kubelet itself uses
systemReserved:
  cpu: "100m"
  memory: "200Mi"      # what the host OS uses (sshd, journald, etc.)
evictionHard:
  memory.available: "100Mi"
  nodefs.available: "10%"
maxPods: 30            # default 110 — too high for a Pi
```

Subtract `kubeReserved + systemReserved + evictionHard` from the node's RAM → that's what's left for Pods. Set requests/limits accordingly.

**Swap is alpha in 1.32.** Set `failSwapOn: false` + `memorySwap.swapBehavior: LimitedSwap` if you want to use it.

---

## The mental model

```
kubeadm builds a Kubernetes the spec exhaustively documents.
k3s/k0s build "Kubernetes minus the parts you don't need."
Managed clusters build "Kubernetes plus operational guarantees."

The API is identical. Your kubectl skills transfer everywhere.
```

The exam tests kubeadm because it tests the **full surface**. In your day job you'll probably never run `kubeadm init` for real — and that's fine.

---

## K8s in the wild — curiosities

Where Kubernetes is actually running today, beyond the typical data center:

- **Every Chick-fil-A restaurant** — k3s on three small boxes, GitOps-managed from HQ. ~2,800 clusters. The original "edge k8s at scale" case study.
- **5G mobile core networks** — basically all of them. Ericsson, Nokia, Cisco, Open-RAN — k8s is the runtime for network functions that used to be appliances.
- **In orbit** — Spire Global runs k3s clusters on satellites; orchestrates sensor workloads across constellations. Lockheed Martin runs k8s on the LM-400 satellite bus.
- **Submarines and naval combat systems** — Lockheed's AEGIS combat-system modernization uses k8s for distributed sensor fusion.
- **Industrial / factory floors** — Siemens, Rockwell, Schneider ship k8s on PLCs. KubeEdge and OpenYurt extend the model to disconnected operation (assume control plane is hours away).
- **Trains and ships** — Deutsche Bahn runs k3s on ICE trains for onboard services. Multiple shipping lines run k3s in vessel server rooms.
- **Autonomous vehicles** — most AV companies use k8s in dev/sim infra; some (e.g. some delivery-bot startups) run k3s **on the vehicle** for sensor processing.
- **Air-gapped government and finance** — fully offline clusters with mirrored registries, signed images, and zero outbound internet. Most pain comes from "no kubectl logs to a cloud bucket."

Common thread: **k8s won everywhere** because the API is the same whether you're on AWS or on a moving train. Skills transfer.

---

## Immutable host OS — the next layer down

"Normal" Linux + k8s is two operational surfaces: the OS (SSH, apt, systemd) AND the cluster. **Immutable OSes collapse this to one.**

| OS | From | Idea |
|---|---|---|
| **Talos Linux** | Sidero Labs | No SSH, no shell, no package manager. Whole OS is k8s-shaped. Configure via gRPC API; reboot to apply. *"The cluster IS the OS."* |
| **Bottlerocket** | AWS | Atomic image-based root FS (RPM-OSTree). SSH only via a control container. Designed for ECS and EKS but works anywhere. |
| **Flatcar Container Linux** | (community) | Successor to CoreOS Container Linux (Red Hat retired CoreOS). Atomic A/B updates, Ignition-style config. |
| **Fedora CoreOS** | Red Hat | Same family; auto-updating immutable OS for container workloads. |

What changes operationally:

- **No SSH-into-a-node and edit a file.** Config is declarative, pushed from outside (Ignition, Talos API, GitOps).
- **Updates are atomic.** A failed update rolls back automatically. No `apt-get upgrade` half-states.
- **Smaller attack surface.** No package manager → no supply-chain attack via apt. No shell → no live exploitation path. No setuid binaries.
- **Different debugging mindset.** When you can't SSH, you `kubectl debug node/...` or you read the audit log. The CKA troubleshooting playbook still works; what changes is how you reach the node.

CKA doesn't test these directly, but the **immutable + GitOps** pattern is what modern clusters look like. Talos in particular is having a moment in 2026 — it's the example to know.

---

## Risky environments — what changes when you can't reach the cluster

Edge, satellite, submarine, air-gapped: the cluster has to keep working with **no human in the loop**.

- **GitOps is non-negotiable.** Argo CD or Flux watches a git repo and reconciles. You push commits; the cluster pulls them at the next sync. Disconnection just means the sync is later.
- **Mirrored registries.** Pull-through caches (Harbor, distribution) or air-gapped registries (sealed registry + signed manifests). No `docker pull` from Docker Hub mid-mission.
- **Local DNS, local PKI.** Self-signed CA distributed via Ignition / Talos config; cert rotation handled by cert-manager with an internal Issuer.
- **Disconnected node operation.** KubeEdge / OpenYurt let a node run for hours/days disconnected from the control plane and resync when reachable. The control plane plans for partition, not assumes connectivity.
- **Smaller-than-quorum failure modes.** A 3-node satellite cluster losing 2 nodes in a solar event still has to do *something*. Single-node operation patterns matter more than HA voting at the edge.
- **Trust, not networking.** When you can't reach a node to revoke its kubelet cert, what stops a stolen unit from joining a fleet? Hardware attestation (TPM-backed boot), short-lived join tokens, and signed bootstrap configs. The frontier of cluster security.

If you take one thing from this section: **k8s in 2026 runs in places nobody imagined when k8s was designed for Google data centers in 2014.** That's the headline.

---

# Live demo: k3s in 60 seconds

```sh
# On the Debian VM directly (after deleting kind):
sudo -i
sudo systemctl disable kubelet               # don't conflict with kubeadm's kubelet
sudo systemctl stop kubelet
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.36.1+k3s1 sh -
sudo k3s kubectl get nodes
sudo k3s kubectl get pods -A
```

Compare:
- Boot time vs kubeadm init (~30s vs ~2min)
- RAM footprint (`free -h`) vs kubeadm cluster
- `kubectl get pods -A` — fewer pods running

Reset with `sudo kubeadm reset --force` + re-init from Lab 7 brief, or
just continue on whatever cluster is up for Lab 8.

---

## etcd — the database

Holds **all cluster state**. If etcd is gone, the cluster is gone.

- Runs as a **static pod** on each control-plane node (kubeadm default)
- TLS-mutual auth via certs in `/etc/kubernetes/pki/etcd/`
- Listens `:2379` (clients), `:2380` (peer-to-peer)
- Uses **Raft** consensus — odd-numbered membership (3 or 5)
- Quorum: `floor(N/2) + 1`. Lose more than that → cluster halts writes.

**Backup is non-negotiable.** Schedule a snapshot at least every 6h on production.

---

## etcd snapshot save

```sh
ETCDCTL_API=3 etcdctl snapshot save /tmp/snap.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

ETCDCTL_API=3 etcdctl snapshot status /tmp/snap.db -w table
# +----------+----------+------------+------------+
# |   HASH   | REVISION | TOTAL KEYS | TOTAL SIZE |
# +----------+----------+------------+------------+
# | 8c1a... |   12345  |   2317     |   4.2 MB   |
# +----------+----------+------------+------------+
```

Memorize the four flag names: `--endpoints --cacert --cert --key`. Practice until you can type them without docs.

---

## etcd restore flow

```sh
# 1. Stop control plane: move static manifests out
sudo mv /etc/kubernetes/manifests /etc/kubernetes/manifests.bak

# 2. Wait for kubelet to tear down the static pods
sudo crictl ps                   # should be empty for cp components

# 3. Restore to a NEW data dir (don't overwrite the live one)
sudo ETCDCTL_API=3 etcdctl snapshot restore /tmp/snap.db \
  --data-dir=/var/lib/etcd-restore

# 4. Swap data dirs
sudo mv /var/lib/etcd /var/lib/etcd.old
sudo mv /var/lib/etcd-restore /var/lib/etcd

# 5. Restart control plane
sudo mv /etc/kubernetes/manifests.bak /etc/kubernetes/manifests

# 6. Verify
sudo crictl ps                   # apiserver + etcd back
k get nodes
```

⚠️ The etcd static pod manifest mounts `/var/lib/etcd` from the host. The data-dir name in the YAML must match where you restored.

---

# Lab 8 — etcd backup & restore

→ `trainees/day4/labs/lab8-etcd-backup.md`

**45 min.**
- Take a snapshot
- Create some objects (a Deployment, a CM)
- Delete them
- Restore from the snapshot
- Verify the deleted objects are back

**This is on every CKA exam in some form.** Practice until it's muscle memory.

---

# CRDs and operators — the extension model

Kubernetes is extensible *at runtime*. The two main mechanisms:

1. **CRD (Custom Resource Definition)** — register a new Kind with the apiserver. Now you can `kubectl get <yourkind>`.
2. **Operator** — a controller that watches your CRD and reconciles real-world state to match. Same pattern as built-in controllers.

You don't write operators on the CKA. You should be able to **recognize** them, install them, debug them.

---

## A CRD example

```yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata: { name: backups.example.com }
spec:
  group: example.com
  scope: Namespaced
  names:
    plural: backups
    singular: backup
    kind: Backup
    shortNames: [bk]
  versions:
    - name: v1
      served: true
      storage: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              properties:
                schedule: { type: string }
                retention: { type: integer }
              required: [schedule]
```

After this CRD is applied, `kubectl get backups -A` and `kubectl explain backup.spec` work.

---

## Custom Resource (CR)

```yaml
apiVersion: example.com/v1
kind: Backup
metadata: { name: nightly, namespace: prod }
spec:
  schedule: "0 2 * * *"
  retention: 14
```

A CR is just a YAML object that conforms to the CRD's schema. Stored in etcd like every other object.

A CR **alone** does nothing — same as an Ingress alone. You need a controller to act on it.

---

## What an operator looks like

Most operators ship as a Deployment in some namespace + RBAC + the CRD.

```sh
k apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml
k get crd | grep cert-manager
# certificaterequests.cert-manager.io
# certificates.cert-manager.io
# clusterissuers.cert-manager.io
# ...
k -n cert-manager get pods
# cert-manager-*           Running   ← the controller
# cert-manager-webhook-*   Running
# cert-manager-cainjector-*
```

The controller watches Certificate CRs and creates real Secrets containing TLS material. Same reconcile pattern.

---

## Debug an operator

If your CR sits there doing nothing:

1. `k describe <cr>` — look for status conditions and events
2. `k -n <operator-ns> logs <operator-pod>` — what is the controller saying
3. `k get apiservice` — if it's an aggregated API (rare), is it `Available: True`?
4. `k get crd | grep <group>` — CRD installed? Versions match what you're applying?
5. RBAC — operator SA must have permissions on every Kind it touches

---

## When you'll see operators on the exam

CRDs are *conceptual* on CKA — they may ask you to:
- Identify what a CRD is from its YAML
- Apply a provided CR after a CRD is installed
- Read events/status from a CR
- Understand why "nothing is happening" (operator pod down)

You won't write a CRD from scratch.

---

# Lab 8b — CRDs & operators

→ `trainees/day4/labs/lab8b-crds.md`

**30 min.**
- Install cert-manager
- Inspect installed CRDs
- Create a self-signed Issuer + a Certificate
- Watch the controller create the Secret
- Break the operator (delete its Deployment); watch reconciliation stop

---

## RBAC + ServiceAccounts revisited for troubleshooting

The shape of a "permission denied" error:

```
Error from server (Forbidden): pods is forbidden: User "system:serviceaccount:ns:sa"
cannot list resource "pods" in API group "" in the namespace "ns"
```

Read it carefully: who, what verb, what resource, what API group, what namespace.

Then:

```sh
k auth can-i list pods -n ns --as=system:serviceaccount:ns:sa
k -n ns get rolebindings -o wide
k -n ns describe rolebinding <name>
```

---

## Troubleshooting playbook (the order)

```
1. kubectl get <kind>          ← status?
2. kubectl describe <kind>      ← events at the bottom?
3. kubectl logs <pod>           ← --previous if crashed; -c for multi-container
4. Node level                  ← journalctl -u kubelet
                                 crictl ps -a / crictl logs
5. Component level             ← /etc/kubernetes/manifests/*
                                 kube-apiserver logs (via container)
6. Network                     ← endpoints, NetworkPolicy, DNS
                                 nslookup from a pod
7. Auth                        ← kubectl auth can-i; RBAC
```

This is your decision tree. Memorize it. Run it top-down on every broken thing.

---

## Logging — what kubectl gives you

```sh
k logs <pod>
k logs <pod> -c <container>            # multi-container
k logs <pod> --previous                # last crash
k logs -f <pod>                        # stream
k logs -l app=web --max-log-requests=20 --tail=50

# from a node, raw:
sudo journalctl -u kubelet -n 200 --no-pager
sudo ls /var/log/pods/<ns>_<pod>_<uid>/<container>/
sudo crictl ps -a
sudo crictl logs <id>
```

Logs come from container stdout/stderr → kubelet → `/var/log/pods/...` → kubectl streams.

If a container writes to a **file**, kubelet doesn't see it. Use a sidecar to tail to stdout.

---

## Cluster-wide logging architecture

| Pattern | How | When |
|---|---|---|
| **Node-level DaemonSet** | Fluent Bit / Vector / Promtail tails `/var/log/containers/*.log` on every node, ships to central store | 90% of clusters |
| **Sidecar** | Extra container in each pod streams app log files | App can't write to stdout; legacy apps |
| **App pushes directly** | App library sends to backend | Loses node context; ad-hoc |

Production backends: Loki, Elastic/OpenSearch, Datadog, CloudWatch, GCP Logging.

Out of CKA exam scope, but you should know the **shape** of the pipeline.

---

## Metrics — metrics-server

Required for `kubectl top` and HPA.

```sh
k apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# on kind, edit metrics-server deployment, add to container args:
# - --kubelet-insecure-tls

k top nodes
k top pods -A
```

`metrics-server` serves the `metrics.k8s.io` API. It is **not** Prometheus — it only keeps the *most recent* metrics in memory.

For real monitoring: **kube-prometheus-stack** Helm chart (Prometheus + Grafana + Alertmanager + node-exporter). Out of CKA scope.

---

## The common failure table

| Symptom | First command | Then |
|---|---|---|
| Node `NotReady` | `journalctl -u kubelet -n 100` on that node | container runtime? swap? cert expired? |
| Pod `Pending` | `k describe pod` events | scheduling: insufficient cpu, taints, affinity |
| Pod `ImagePullBackOff` | `k describe pod` | typo, private registry → `imagePullSecrets` |
| Pod `CrashLoopBackOff` | `k logs --previous` | exit code; entrypoint; failing probe |
| Pod `CreateContainerConfigError` | `k describe pod` | referenced CM/Secret doesn't exist |
| Service unreachable | `k get endpoints <svc>` | empty? selector wrong / pods not Ready |
| DNS broken | `k -n kube-system get pods -l k8s-app=kube-dns` | CoreDNS logs; Corefile |
| API hangs / no response | apiserver static pod; etcd | `/etc/kubernetes/manifests/`; `crictl logs` |
| `Forbidden` errors | `k auth can-i ...` | RBAC: Role + Binding |

---

## Static pod recovery

If apiserver / scheduler / controller-manager / etcd is broken:

```sh
ls /etc/kubernetes/manifests/
sudo cat /etc/kubernetes/manifests/kube-apiserver.yaml
```

Edit the file — kubelet sees the change in ~10s and restarts the pod.

If you broke it badly:

```sh
sudo mv /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/
# kubelet tears it down
sudo crictl ps                                              # confirm gone
# fix the file, move it back
sudo mv /tmp/kube-apiserver.yaml /etc/kubernetes/manifests/
```

This is the **only** way to "restart" a control plane static pod. There's no `systemctl restart kube-apiserver`.

---

## Network troubleshooting flow

```
Service unreachable
  → check endpoints (empty? → selector / readiness / pods)
  → from a pod: nslookup <svc>     (DNS? → CoreDNS)
  → from a pod: curl <svc-ip>      (kube-proxy? iptables? CNI?)
  → check NetworkPolicy on source + dest
  → check kube-proxy logs on the receiving node
```

Spawn a debug pod with networking tools:
```sh
k run dbg --rm -it --image=nicolaka/netshoot -- bash
> dig +search +noall +answer web
> curl -v http://web
> tcpdump -ni any port 80
> ss -tlpn
```

---

# Lab 9 — Troubleshooting

→ `trainees/day4/labs/lab9-troubleshooting.md`

**45 min.** Trainer assigns ONE of four scenarios at random:

- **A. Broken kubelet** on a node (service config wrong)
- **B. Broken control plane** (corrupt static pod manifest)
- **C. Broken DNS** (CoreDNS Corefile loop / wrong upstream)
- **D. Broken app** (probe, image, RBAC, NetworkPolicy — pick one)

Diagnose, fix, prove. Write the root cause in `/tmp/lab9-rca.txt` (good habit for the exam).

---

# Mock Exam

→ `trainees/day4/labs/mock-exam.md`

**75 minutes.** 13 questions. No notes. No Google. No AI.

Allowed: `kubernetes.io/docs`, `helm.sh/docs`, `kubernetes.io/blog`.

Set a hard timer. Trainer reviews after time is up.

---

## Exam-day strategy — the rules I'd give myself

- **Skim ALL questions first** (5 min). Mark easy / medium / hard. Solve easy first.
- Every question has a **weight (%)**. A 10% question is worth 2.5× a 4% question.
- **Set context + namespace on every question.** Forgetting costs you the whole question.
- **Stuck > 8 min?** Flag and move on. Come back at the end.
- Use `k explain --recursive <kind>` instead of digging through docs pages.
- Use `$do` to generate; edit; apply. Don't type Pod YAML from scratch.
- `k edit` is dangerous — easy to mess up YAML in vim with no undo to last apply.
- Always verify with the question's success criteria *before* moving on (a service "must work" means `curl` it).

---

## Day-of logistics

- **Eat first.** No food during the exam.
- **Water in a clear glass.** Proctor needs to see through it.
- **Clear desk.** Proctor will scan the room before starting.
- **One monitor.** Disconnect external displays.
- **Chrome only.** Firefox/Safari are not supported by PSI.
- **Bathroom break** is permitted once (newer rule; check the current Candidate Handbook).
- **ID:** government ID with Latin characters (passport is safest).

---

## After the exam

- Result via email in ~24 hours
- **If you fail:** 1 free retake within 12 months. Book it **2 weeks out**, do killer.sh once more in between.
- **If you pass:** digital badge on Credly, valid **2 years**.

---

## Where to go next

- **CKS** (Certified Kubernetes Security Specialist) — needs active CKA, 2-year window
- **KCSA** — security associate, no prereq
- **CKAD** — developer counterpart (some overlap, less ops)
- Real-world skill stack: Helm chart authoring, GitOps (Argo CD / Flux), service mesh (Istio/Linkerd), observability (Prometheus + Grafana + Loki)
- Operator authoring (Kubebuilder, Operator SDK) — natural Day 5 if this becomes a habit

---

## Wrap-up

Thank you for the four days. Three things to do this week:

1. **killer.sh session 1** within 7 days (it will feel impossibly hard — that's the point)
2. **Schedule the exam** (book a date — accountability matters)
3. **Re-run the mock exam** from this course on a fresh kind cluster

Questions?
