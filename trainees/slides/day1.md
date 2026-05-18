---
marp: true
theme: default
paginate: true
size: 16:9
header: "CKA Intensive — Day 1"
footer: "© Luis Torres"
style: |
  section { font-size: 24px; }
  pre, code { background: #1e1e1e; color: #eee; }
  h1 { color: #326ce5; }
  h2 { color: #326ce5; border-bottom: 2px solid #326ce5; }
  table { font-size: 22px; }
---

# CKA Intensive
## Day 1 — Foundations, Architecture, Workloads, Config

Luis Torres
4-day intensive · **target: Kubernetes v1.36** (kind labs run on v1.35.1 — kind hasn't shipped a v1.36 node image yet; kubeadm lab on Day 4 runs v1.36.1)

---

## Today

1. Welcome + exam logistics
2. **Containers from scratch** — namespaces, cgroups, overlayfs, OCI, CRI
3. Kubernetes architecture (deep) — apiserver, etcd/Raft, scheduler, kubelet/PLEG, kube-proxy, CNI
4. The API + reconciliation model
5. **Lab 0** — bootstrap your Multipass cluster + take baseline snapshot
6. kubectl mastery
7. **Lab 1** — kubectl basics
8. Workload controllers — Pod → Deployment → DaemonSet → StatefulSet → Job → CronJob
9. **Lab 2** — workloads
10. ConfigMaps, Secrets, Probes, init containers
11. **Lab 2b** — config + probes

---

## The exam at a glance

- **2 hours**, performance-based — no multiple choice
- ~15–20 hands-on tasks, each weighted by %
- **Pass: 66%** (lowered from 74% in 2024)
- Cost: ~$395 USD, includes **1 free retake** within 12 months
- **2 free killer.sh sessions** (harder than the real exam — use both)
- Allowed docs: `kubernetes.io/docs`, `kubernetes.io/blog`, `helm.sh/docs`
- Browser-based, **PSI proctored, Chrome only**
- Result in ~24h by email
- Digital badge on Credly, valid **2 years**

---

## Curriculum weights (2024 refresh, still current)

| Domain | Weight |
|--------|--------|
| Cluster Architecture, Install & Config | 25% |
| Workloads & Scheduling | 15% |
| Services & Networking | 20% |
| Storage | 10% |
| **Troubleshooting** | **30%** |

**Implication:** Troubleshooting is the biggest single category — Day 4 spends most of itself there. But every domain *also* contains troubleshooting in disguise.

---

## What the 2024 refresh added vs old curriculum

If you've seen older CKA prep material — these are new and **on the exam**:

- **Helm** + **Kustomize** (cluster architecture)
- **Gateway API** alongside Ingress (networking)
- **HPA / autoscaling** (workloads)
- **CRDs and operators** (cluster architecture, conceptual)
- **Dynamic volume provisioning** is now explicitly emphasized

We cover all of these. Older course material that skips them will leave you a half-letter-grade short.

---

# Containers from scratch

Before we can orchestrate them, we need to know what they **are**.

---

## A container is not a tiny VM

A container is a **normal Linux process** the kernel has been told to lie to about three things:

| Lie | Mechanism |
|-----|-----------|
| What's in the filesystem | mount namespace + overlayfs |
| What other processes exist | PID namespace |
| What the network looks like | network namespace |
| How much CPU/RAM it can use | cgroups v2 |
| Which users exist (optional) | user namespace |

No special kernel, no hypervisor, no virtualization. Just **namespaces + cgroups + a layered filesystem.**

---

## Namespaces in /proc

```sh
docker inspect demo --format '{{.State.Pid}}'   # → 12345
sudo ls -l /proc/12345/ns/
# ipc -> ipc:[4026532245]
# mnt -> mnt:[4026532244]
# net -> net:[4026532247]
# pid -> pid:[4026532246]
# user -> user:[4026531837]
# uts -> uts:[4026532243]
```

**Same namespace ID = same container.** Two processes are "in the same container" exactly when these symlinks point to the same target.

`docker exec` is just `setns(2)` — attach a new process to existing namespaces.

---

## Why this matters for Kubernetes

A **Pod** = a group of containers sharing some namespaces:

- **Same** `net` namespace → they see each other on `localhost`
- **Same** `ipc` namespace → POSIX/SysV IPC works
- **Different** `mnt` namespace → each has its own root filesystem
- **Different** `pid` namespace → can't see each other's processes (by default)

This is why sidecar containers can `localhost:8080` to the main container — same `net` namespace, two processes on the same loopback.

---

## Images and layers (overlayfs)

```
┌──────────────────────────────────┐
│ layer 4: nginx config            │  ← top, smallest
├──────────────────────────────────┤
│ layer 3: nginx package           │
├──────────────────────────────────┤
│ layer 2: apt cache + libs        │
├──────────────────────────────────┤
│ layer 1: debian:bookworm rootfs  │  ← base, largest
└──────────────────────────────────┘
+ writable layer (per container, ephemeral)
```

Each layer is a tarball of file changes. **Image layers are read-only and shared across all containers** that use them. Each container gets a fresh empty writable layer.

Kill the container → writable layer is destroyed. **This is why we have Volumes.**

---

## cgroups enforce limits

```sh
docker run --memory=50m alpine sh -c \
  'dd if=/dev/zero of=/big bs=1M count=200'
# → Killed (OOM)
dmesg | tail
# [12345.678] Memory cgroup out of memory: Killed process 12345 (dd)
```

The kernel's OOM killer fires when a cgroup exceeds its memory limit. **Exactly what happens to a Pod that exceeds its `resources.limits.memory`.**

CPU works similarly: cgroup `cpu.cfs_quota / cpu.cfs_period` throttles, doesn't kill.

---

## OCI: images are a standard

The **Open Container Initiative** standardizes:
- **Image format** — directory of tarballs + JSON manifest
- **Runtime spec** — how to launch one container
- **Distribution spec** — how registries serve images

```
nginx:1.27   ← tag (mutable pointer)
  └─ sha256:abc...  ← digest (immutable content hash)
       └─ layers + config JSON
```

Docker builds, containerd runs, CRI-O runs, Podman does both — **all the same image format**. Build on your laptop, run on a cluster that has never heard of Docker.

---

## CRI: how Kubernetes talks to runtimes

```
   kubelet ─── gRPC ───▶  containerd  ─── kernel ───▶  namespaces + cgroups
        (CRI)                  (or CRI-O)
```

**Kubernetes does not "use Docker."**
- The kubelet speaks the Container Runtime Interface (CRI) to whatever runtime is installed.
- Containerd implements CRI directly. CRI-O implements CRI directly.
- The old `dockershim` was removed in **Kubernetes 1.24** — it was an in-tree adapter for an out-of-tree tool.

On our nodes, kubelet talks to containerd at `/run/containerd/containerd.sock`.

---

## Take-away: the mental model

```
container        = process + namespaces + cgroups + overlayfs layers
image            = a stack of tarballs + a JSON manifest
registry         = HTTP server speaking the OCI Distribution spec
runtime          = the thing that turns an image into a running container (containerd, CRI-O)
CRI              = the API the kubelet uses to talk to the runtime
```

If "container" was fuzzy 90 minutes ago and now it isn't — that's the foundation everything else stands on.

---

## What Kubernetes is (in one sentence)

> A cluster API for declaring the **desired state** of containerized workloads, with **controllers** that reconcile actual state to match.

Three ideas that explain almost everything:

1. **Declarative** — you describe *what*, controllers figure out *how*.
2. **Eventually consistent** — there is *always* skew between what you asked for and what's running. The system converges.
3. **Everything is an object** — every kind has the same lifecycle: create, get, watch, update, delete.

---

## Architecture — the whole picture

![bg right:38% 95%](https://kubernetes.io/images/docs/components-of-kubernetes.svg)

**Control plane** (one set per cluster, typically on dedicated nodes):
- kube-apiserver
- etcd
- kube-scheduler
- kube-controller-manager
- cloud-controller-manager *(optional)*

**Every node** (control plane and worker):
- kubelet
- kube-proxy
- container runtime (containerd/CRI-O)
- CNI plugin

---

## kube-apiserver

The **only** thing anyone or anything talks to. Everything else is a client.

- REST API over HTTPS (`:6443`)
- Authn (certs, tokens, OIDC, webhook) → Authz (RBAC, Node, Webhook) → Admission (mutating + validating) → etcd
- **Watches:** clients open a long-lived HTTP stream; apiserver pushes object changes
- Stateless — scale horizontally; etcd is the only stateful piece

The watch/list/reconcile loop is *the* Kubernetes pattern. Every controller is one.

---

## Inside the apiserver — the request chain

Every request walks the same chain:

```
   client
     │
     ▼
  ┌─────────────────┐
  │  authentication │  who are you?   (cert / token / OIDC / webhook)
  ├─────────────────┤
  │  authorization  │  are you allowed?   (RBAC, Node, Webhook)
  ├─────────────────┤
  │  mutating       │  modify the object  (defaults, sidecar injection)
  │  admission      │
  ├─────────────────┤
  │  schema valid.  │  conforms to OpenAPI?
  ├─────────────────┤
  │  validating     │  policy / quota / PSA
  │  admission      │
  ├─────────────────┤
  │  etcd write     │
  └─────────────────┘
```

Reject at any layer → request dies with the relevant HTTP code.
**Most "weird" creation failures land in admission.** `kubectl describe events` is your friend.

---

## What is etcd?

A **distributed, strongly-consistent key/value store**. Named after Unix's `/etc` (config) + `d` (distributed) — "distributed /etc."

- Created at **CoreOS in 2013** for their Container Linux distro.
- Donated to the **CNCF in 2018**; graduated project alongside Kubernetes.
- Written in Go. Single binary. gRPC API.

**Why not just use Postgres / Redis / a file?**

| | etcd | Postgres / MySQL | Redis | ZooKeeper |
|---|---|---|---|---|
| Consistency | Strong (every read sees latest write) | Strong on primary, eventual on replicas | Async replication, can lose writes | Strong (ZAB protocol) |
| API | Flat KV + watch | SQL, joins, indexes | KV + data structures | Hierarchical znodes |
| Sweet spot | Small (GBs), critical config | Large datasets, rich queries | Speed, cache | Coordination |
| Write ceiling | ~10K/sec | 100K+/sec | 1M+/sec | ~10K/sec |

etcd is **optimized for cluster coordination**, not bulk storage. Every write goes through Raft consensus → durable + consistent, but slower than a single-node DB. Kubernetes uses it for cluster state (pods, services, configmaps) — never for metrics or logs.

---

## etcd in Kubernetes

- All cluster state lives here. Lose etcd → lose the cluster.
- Runs as a **static pod** on control-plane nodes by default (kubeadm)
- **Listens on `:2379`** (clients) and `:2380` (peer-to-peer)
- TLS-protected, certs in `/etc/kubernetes/pki/etcd/`
- Recommended: odd number of members (3 or 5) for quorum

You will back it up and restore it on Day 4. Memorize the commands.

---

## Raft, in one slide

Raft is a **leader-based consensus algorithm**. At any time:

- One member is **leader**, the rest are **followers**.
- Clients (apiserver) write to the leader.
- Leader appends to its log, replicates to followers.
- Once a **majority** has acknowledged → entry is **committed** → applied to the state machine.

```
3 nodes → quorum = 2 → tolerate 1 failure
5 nodes → quorum = 3 → tolerate 2 failures
2 nodes → quorum = 2 → tolerate 0 failures   (worse than 1 node)
```

**Always odd numbers.** This is why control-plane HA recommendations are 3 or 5.

If the leader dies, followers detect via missed heartbeats, hold an election, a new leader emerges. Writes pause briefly during election (~1-2s).

---

## Why Raft? (and not Paxos, or eventual consistency)

**Paxos** (Lamport, 1989) was the original distributed consensus algorithm. Mathematically sound — and notoriously hard to understand. Google's Chubby and Spanner use Paxos variants. Most engineers who implement Paxos get it subtly wrong.

**Raft** (Ongaro & Ousterhout, Stanford, 2014) was designed with one goal: **understandability**. Same correctness guarantees as Paxos, decomposed into three independent subproblems:
1. **Leader election** — who's in charge right now?
2. **Log replication** — leader streams entries to followers.
3. **Safety** — once committed, an entry survives any future leader.

Result: more correct implementations, easier to operate. **etcd, Consul, CockroachDB, TiKV, MongoDB (5.0+)** all use Raft.

**Why not eventual consistency** (Dynamo / Cassandra style)? Kubernetes can't tolerate split-brain on cluster state. Two apiservers each believing a different pod owns the same IP = data corruption. Strong consistency is non-negotiable for the control plane — and you pay for it with the quorum-write latency.

---

## kube-scheduler

Watches for **pods without `nodeName`** and assigns one.

Two phases:
1. **Filter** — which nodes are eligible? (taints, affinity, port conflicts, resource requests)
2. **Score** — among eligible, which is best? (spread, image locality, etc.)

Picks the highest-scoring node and writes `pod.spec.nodeName` back to etcd via apiserver.

Doesn't actually start the pod — that's kubelet's job.

---

## Scheduling algorithm — what runs in filter and score

**Filter plugins** (must pass ALL):
- `NodeUnschedulable`, `NodeName`, `NodeAffinity`, `NodeResourcesFit`
- `TaintToleration`, `NodeVolumeLimits`, `VolumeBinding`, `VolumeRestrictions`
- `InterPodAffinity`, `PodTopologySpread` (filter side)

**Score plugins** (numeric, summed):
- `NodeResourcesBalancedAllocation` — prefer evenly-used nodes
- `NodeResourcesFit` (LeastAllocated by default) — prefer free nodes
- `ImageLocality` — prefer nodes that already cached the image
- `InterPodAffinity` (score side), `PodTopologySpread` (score side)
- `TaintToleration`, `NodeAffinity` (score side)

`kubectl describe pod` shows the failing **filter** in the events:
```
0/3 nodes are available: 1 Insufficient cpu, 2 node(s) had untolerated taint.
```

---

## kube-controller-manager

A single binary running **many** built-in controllers as goroutines:

- Deployment controller, ReplicaSet controller, DaemonSet, StatefulSet, Job, CronJob
- Node controller (mark NotReady), endpoint(slice) controller, namespace, SA, GC, ...

Each one is a watch loop: *observe → diff desired vs actual → take action*.

The reconciliation pattern is identical for built-in and custom controllers. Once you understand one, you understand all of them.

---

## cloud-controller-manager

Talks to your cloud provider's API.

- LoadBalancer Services → provision an actual cloud LB
- Node lifecycle (was this VM deleted? mark Node deleted)
- Routes (where needed)

Only present when you're on a cloud (EKS/GKE/AKS/etc.). On kind/kubeadm-on-bare-metal, absent — which is why `LoadBalancer` Services stay `Pending` on kind unless you install MetalLB or cloud-provider-kind.

---

## kubelet

The agent on every node. The control plane's hands and eyes.

- Watches apiserver for **pods assigned to this node**
- Talks to the **CRI runtime** to pull images and run containers
- Reports node status + pod status back to apiserver
- Runs **probes** (liveness/readiness/startup)
- Mounts volumes for pods
- Reads **static pod manifests** from `/etc/kubernetes/manifests/` — that's how control-plane pods themselves run

If kubelet stops: node goes `NotReady`. Existing pods keep running until the kernel reaps them.

---

## Inside the kubelet — the sync loop

```
   ┌─────────────────────────────────────────────┐
   │  syncLoop (every 10s + on events)           │
   │                                             │
   │   for each pod assigned to this node:       │
   │     desired = pod.spec                      │
   │     actual  = PLEG (Pod Lifecycle Event Gen)│
   │     diff = reconcile(desired, actual)       │
   │     apply(diff) via CRI                     │
   └─────────────────────────────────────────────┘
```

**PLEG** (Pod Lifecycle Event Generator) polls the runtime every second to detect:
- Container started / stopped / exited / OOMKilled
- Pod sandbox died

When PLEG is slow (overloaded node, hung containerd), you see:
```
PLEG is not healthy: pleg was last seen active 3m32s ago
```
→ kubelet reports node `NotReady`. Day 4 troubleshooting symptom.

---

## kube-proxy

Programs the **node's networking** so Service VIPs work.

Three modes (1.32):
- **iptables** — default; rules per Service+endpoint; O(n) traversal
- **IPVS** — kernel-level load balancer; better at high scale
- **nftables** — GA in 1.32; modern replacement for iptables mode

Without kube-proxy, you can still create Services, but the VIP won't route anywhere. Some CNIs (Cilium with eBPF) replace kube-proxy entirely.

---

## What kube-proxy actually writes

For Service `web` (ClusterIP `10.96.50.10:80`) with three pods:

```sh
sudo iptables -t nat -L KUBE-SERVICES -n
# Chain KUBE-SERVICES
# DNAT tcp -- 10.96.50.10:80 → KUBE-SVC-WEB

sudo iptables -t nat -L KUBE-SVC-WEB -n
# 1/3 chance → KUBE-SEP-POD1 → DNAT to 10.244.1.5:8080
# 1/2 chance → KUBE-SEP-POD2 → DNAT to 10.244.2.7:8080
# 100% chance → KUBE-SEP-POD3 → DNAT to 10.244.1.9:8080
```

**The Service VIP is never actually listening anywhere.** `ss -tlnp` won't find it. The kernel rewrites the destination at packet-arrival time. This catches everyone the first time they try to "ping" a Service.

---

## Container Runtime (CRI)

Kubernetes doesn't run containers — it asks a CRI-compliant runtime to.

- **containerd** (most common on managed clouds and kubeadm)
- **CRI-O** (Red Hat / OKD)
- ❌ **Docker is gone** — dockershim removed in v1.24

`crictl` is your debugging tool on a node (similar to `docker` CLI, but talks to CRI):

```sh
sudo crictl ps -a            # list containers
sudo crictl logs <id>
sudo crictl inspect <id>
sudo crictl pods             # list pod sandboxes
```

---

## CNI (Container Network Interface)

The plugin that gives **pods their IPs and connectivity**.

| CNI | Strengths |
|---|---|
| **Calico** | Mature; NetworkPolicy enforcement; BGP; eBPF mode |
| **Cilium** | eBPF-native; kube-proxy replacement; Hubble observability; Gateway API |
| **Flannel** | Simple; no policy |
| **Weave** | Maintenance has slowed |
| **kindnet** | Default in `kind`; **does NOT enforce NetworkPolicy** |

Without a CNI, nodes are `NotReady` and pods can't get IPs.

---

## What a CNI actually does (veth + bridge)

When a pod is scheduled to a node, kubelet calls the CNI binary with:
```
ADD  <pod-id>  <netns-path>  ...
```

The CNI plugin (e.g., Calico) creates:

```
         ┌─────────── pod netns ───────────┐
         │  eth0 (10.244.1.5)              │
         └──────────────┬──────────────────┘
                        │  veth pair
   ┌────────────────────┴──────────────────────────┐
   │  host netns: vethABC (peer)                   │
   │      │                                        │
   │      ▼                                        │
   │  cni0 bridge  ──►  iptables ──► eth0  ──► wire│
   └───────────────────────────────────────────────┘
```

- **veth pair**: a virtual cable; one end inside the pod, one end on the host.
- **cni0 bridge** (or per-CNI equivalent): layer-2 switch joining all local pods.
- Routes / BGP / VXLAN handle pod→pod across nodes (CNI-specific).

`ip addr` on the host shows the veth ends. `crictl inspect <pod>` shows the pod's namespace path.

---

## How a Pod gets created — full path

1. `kubectl apply -f pod.yaml`
2. **apiserver:** authn → authz → admission → write to **etcd**
3. **scheduler** watches unscheduled pods, runs filter+score, writes `nodeName` via apiserver
4. **kubelet** on that node watches its own pods, sees the new assignment
5. kubelet asks **CRI runtime** to pull image and start container(s)
6. kubelet sets up volumes, networks (via CNI), then runs containers
7. kubelet reports `Running` + probe results back to apiserver
8. (If part of a Service) **endpoint(slice) controller** adds pod IP to endpoints
9. **kube-proxy** on every node updates iptables/IPVS rules

Steps 1–3 are seconds. Step 5 dominates wall-clock (image pull).

---

## The mental model: watch / list / reconcile

Every controller (and most user code in operators) does this loop:

```
list("pods") ─── desired ───┐
                            ├─► diff ──► action (create/update/delete)
list("pods") ─── actual ────┘                │
                                             ▼
watch("pods") ─── changes ──────────────► trigger next loop
```

- "List once, watch thereafter" — efficient state synchronization
- **Level-triggered, not edge-triggered:** if you miss an event, the next reconcile fixes it
- Idempotent: applying the same desired state twice is a no-op

---

## Kubernetes objects — anatomy

```yaml
apiVersion: apps/v1            # group/version
kind: Deployment               # kind
metadata:
  name: web
  namespace: prod
  labels: { app: web, tier: frontend }
  annotations: { team: platform }
spec:                          # desired state — you write this
  ...
status:                        # actual state — controllers write this
  ...
```

- **Group/version/kind (GVK)** identifies the schema
- `metadata.name` is unique within `namespace` per kind
- **You write `spec`. You read `status`.** Don't put your state in `metadata`.

---

## Namespaces

A namespace is a **scope** for naming objects, plus a unit for:

- RBAC (per-namespace roles)
- ResourceQuota / LimitRange
- NetworkPolicy
- DNS suffix (`<svc>.<ns>.svc.cluster.local`)

**Not** in any namespace: nodes, PVs, ClusterRoles, StorageClasses, CRDs, the namespace object itself.

```sh
k api-resources --namespaced=true
k api-resources --namespaced=false
```

---

# Lab 0 — Environment

→ `trainees/day1/labs/lab0-environment.md`

**60 min.** Verify Docker, kubectl 1.36.1, kind 0.31, helm v4.2.0, vim. Bring up the 3-node kind cluster on v1.35.1 (kind's latest node image). Verify `kubectl get nodes` shows 3 Ready nodes.

If you can't get past Lab 0 by the end of the slot, tell the trainer — we don't continue with a broken setup.

---

## kubectl — your only friend on exam day

```sh
alias k=kubectl
source <(kubectl completion bash)         # zsh: kubectl completion zsh
complete -o default -F __start_kubectl k

export do='--dry-run=client -o yaml'      # generate YAML
export now='--grace-period=0 --force'     # force delete
```

**Set this in EVERY new terminal on the exam.** They give you a `~/.bashrc` snippet block — paste it.

You don't get tab completion for `k` until you `complete -F __start_kubectl k`.

---

## Imperative vs declarative

```sh
# Imperative — fast, exam-friendly
k run nginx --image=nginx:1.27
k create deploy web --image=nginx:1.27 --replicas=3
k expose deploy web --port=80

# Declarative — production / git-tracked
k apply -f deployment.yaml
```

The pragmatic exam workflow:

```sh
k create deploy web --image=nginx:1.27 $do > web.yaml
vi web.yaml          # add what generator can't (volumes, probes, ...)
k apply -f web.yaml
```

---

## Generators you'll use on the exam

```sh
# pod
k run nginx --image=nginx:1.27 $do > pod.yaml

# deployment
k create deploy web --image=nginx:1.27 --replicas=3 --port=80 $do > dep.yaml

# service
k expose deploy web --port=80 --target-port=80 --name=web $do > svc.yaml
k create svc clusterip web --tcp=80:80 $do > svc.yaml

# configmap / secret
k create cm app --from-literal=KEY=val $do > cm.yaml
k create secret generic db --from-literal=password=p $do > sec.yaml

# job / cronjob
k create job hello --image=busybox -- echo hi $do > job.yaml
k create cronjob c --image=busybox --schedule="*/1 * * * *" -- echo hi $do > cj.yaml

# rbac
k create sa dev $do > sa.yaml
k create role r --verb=get,list --resource=pods $do > role.yaml
k create rolebinding rb --role=r --serviceaccount=ns:dev $do > rb.yaml

# resourcequota
k create quota nq --hard=cpu=2,memory=1Gi,pods=5 $do > q.yaml
```

There is **no generator** for: DaemonSet, StatefulSet, PV/PVC, NetworkPolicy, Ingress, HPA. Start from a Deployment YAML and edit, or copy from `kubernetes.io/docs`.

---

## The 80% of kubectl

| Verb | What it does |
|---|---|
| `get` | list objects (add `-w` to watch, `-o wide`, `-o yaml`, `-o jsonpath=...`) |
| `describe` | human-readable detail; **always check Events at the bottom** |
| `logs` | container logs (`-f`, `--previous`, `-c <container>`, `-l <selector>`) |
| `exec` | run command in container (`-it -- sh`) |
| `apply` | declarative create/update |
| `create`, `run`, `expose` | imperative shortcuts (+ generators with `$do`) |
| `edit` | open in `$EDITOR`; saves on `:wq` |
| `patch` | scripted partial update; better than `edit` for known fields |
| `delete` | remove (+ `$now` for stuck objects) |
| `explain` | schema docs; `--recursive` to see all fields |
| `rollout status/history/undo` | manage Deployment rollouts |

---

## `kubectl explain` — your offline docs

```sh
k explain deployment.spec.strategy --recursive
k explain pod.spec.containers.livenessProbe
k explain networkpolicy.spec.ingress
```

Beats hunting through `kubernetes.io/docs` for field names. **No internet round-trip on the exam.**

For verb-level help:

```sh
k create -h | less
k expose -h | less
```

Read the examples in `-h` — they're better than half the doc pages.

---

## Output formats: `-o jsonpath` and `-o custom-columns`

When `get` isn't enough:

```sh
k get pod web -o jsonpath='{.status.podIP}'
k get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.phase}{"\n"}{end}'

k get nodes -o custom-columns=NAME:.metadata.name,VER:.status.nodeInfo.kubeletVersion

k get pods --sort-by=.metadata.creationTimestamp
k get pods --field-selector=status.phase=Pending -A
```

Worth memorizing one or two patterns for exam questions like *"export the pod name running the highest version of nginx."*

---

## Contexts and namespaces

```sh
k config get-contexts
k config use-context <ctx>
k config set-context --current --namespace=<ns>
k config view --minify                          # what am I pointed at right now?
```

**Every exam question states the context and namespace.** Set both before reading the rest of the question. Forgetting to switch costs you the whole question.

---

# Lab 1 — kubectl basics

→ `trainees/day1/labs/lab1-kubectl-basics.md`

**60 min.** Contexts, imperative, generators, deployments, expose, jsonpath, sort.

The point is **muscle memory**, not understanding. Type, don't paste.

---

## Workload controllers — the family tree

```
Pod                  ← smallest schedulable unit
 │
ReplicaSet           ← keeps N pods running (rarely written directly)
 │
Deployment           ← rolling updates + rollback history
 │
DaemonSet            ← one pod per (selected) node
 │
StatefulSet          ← stable identity + storage, ordered
 │
Job                  ← run to completion (success/failure)
CronJob              ← scheduled Jobs
```

Each controller is one watch/reconcile loop. They differ only in *what they reconcile toward*.

---

## Pod — the atom

A pod is **one or more containers** that share:
- a Linux network namespace (same IP, same port space)
- IPC namespace
- volumes
- (optionally) PID namespace via `shareProcessNamespace`

**One main container per pod is the norm.** Sidecars (log shipper, proxy, fetcher) are valid; init containers are common.

Pods are **mortal**: they are recreated, never resurrected. New pod = new IP. Don't write code that depends on pod IPs.

---

## Minimal Pod YAML

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: web
  labels: { app: web }
spec:
  containers:
    - name: nginx
      image: nginx:1.27
      ports: [{ containerPort: 80 }]
      resources:
        requests: { cpu: 100m, memory: 128Mi }
        limits:   { cpu: 500m, memory: 256Mi }
```

You'll write this YAML in your sleep. Memorize the indentation.

---

## Multi-container pod (sidecar pattern)

```yaml
spec:
  containers:
    - name: app
      image: myapp:1.0
      volumeMounts: [{ name: logs, mountPath: /var/log/app }]
    - name: log-shipper
      image: fluent-bit:3.0
      volumeMounts: [{ name: logs, mountPath: /var/log/app, readOnly: true }]
  volumes:
    - name: logs
      emptyDir: {}
```

The two containers share `logs` via `emptyDir`. Use cases: log shipping, file conversion, service mesh sidecar.

Native sidecar containers (init container with `restartPolicy: Always`) are GA in 1.29 — they start before regular containers and shut down after.

---

## Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata: { name: web }
spec:
  replicas: 3
  selector:
    matchLabels: { app: web }
  template:
    metadata: { labels: { app: web } }
    spec:
      containers:
        - name: nginx
          image: nginx:1.27
          ports: [{ containerPort: 80 }]
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 25%
      maxUnavailable: 0
```

⚠️ **`selector.matchLabels` MUST equal `template.metadata.labels`** (since 1.16, API rejects otherwise).

---

## Rolling update mechanics

```sh
k set image deploy/web nginx=nginx:1.28
k rollout status deploy/web
k rollout history deploy/web
k rollout undo deploy/web --to-revision=2
k rollout pause deploy/web
k rollout resume deploy/web
```

Strategy knobs:

| Knob | Effect |
|---|---|
| `maxSurge: 25%` | up to 25% over desired during rollout |
| `maxUnavailable: 0` | never drop below desired — slower, zero downtime |
| `maxUnavailable: 25%` | up to 25% under desired — faster, brief degradation |
| `type: Recreate` | kill all, then start new — downtime guaranteed |

---

## DaemonSet

One pod per **node** (or per matching subset).

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata: { name: node-watch }
spec:
  selector: { matchLabels: { app: nw } }
  template:
    metadata: { labels: { app: nw } }
    spec:
      tolerations:
        - operator: Exists           # tolerate all taints; needed for cp nodes
      containers:
        - name: agent
          image: busybox:1.36
          command: ["sleep", "86400"]
```

Use for: log shippers, node exporters, CNI agents, kube-proxy itself, CSI drivers.
No `replicas` field. No `strategy` (rolling update via `updateStrategy`).

---

## StatefulSet

For workloads that need:

- **Stable hostnames:** `db-0`, `db-1`, `db-2` — *never* renumbered
- **Stable per-pod storage:** each pod gets its own PVC via `volumeClaimTemplates`
- **Ordered** rollout, scaling, deletion (0 → 1 → 2; reverse on delete)

Requires a **headless Service** (`clusterIP: None`).

Used for: databases (Postgres, MySQL, Mongo), queues (Kafka, RabbitMQ), distributed caches, anything where pod identity matters.

---

## StatefulSet YAML

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata: { name: db }
spec:
  serviceName: db                  # headless Service name
  replicas: 3
  selector: { matchLabels: { app: db } }
  template:
    metadata: { labels: { app: db } }
    spec:
      containers:
        - name: db
          image: postgres:16
          ports: [{ containerPort: 5432 }]
          volumeMounts:
            - { name: data, mountPath: /var/lib/postgresql/data }
  volumeClaimTemplates:
    - metadata: { name: data }
      spec:
        accessModes: [ReadWriteOnce]
        resources: { requests: { storage: 5Gi } }
```

---

## Job & CronJob

```yaml
apiVersion: batch/v1
kind: Job
metadata: { name: pi }
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: pi
          image: perl:5.34
          command: ["perl", "-Mbignum=bpi", "-wle", "print bpi(200)"]
  backoffLimit: 4
  completions: 1
  parallelism: 1
```

```sh
k create cronjob hello --image=busybox \
  --schedule="*/1 * * * *" -- /bin/sh -c 'echo hello at $(date)'
```

CronJob spawns Jobs on a schedule (UTC by default; `timeZone` field in 1.27+ for explicit TZ).

---

# Lab 2 — Workloads

→ `trainees/day1/labs/lab2-workloads.md`

**60 min.** Deployment with rolling update + rollback, DaemonSet, StatefulSet, Job, CronJob.

---

## ConfigMap — non-secret config

```yaml
apiVersion: v1
kind: ConfigMap
metadata: { name: app-config }
data:
  LOG_LEVEL: debug
  TIMEOUT: "30s"
  app.properties: |
    foo=bar
    baz=qux
```

Three ways to consume in a Pod:

1. **Env var by key:** `env: [{ name: LOG_LEVEL, valueFrom: { configMapKeyRef: { name: app-config, key: LOG_LEVEL } } }]`
2. **All keys as env vars:** `envFrom: [{ configMapRef: { name: app-config } }]`
3. **Mount as volume:** each key → file at `mountPath/<key>`

---

## ConfigMap consumed three ways — full example

```yaml
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sleep", "3600"]
      env:
        - name: LOG_LEVEL
          valueFrom: { configMapKeyRef: { name: app-config, key: LOG_LEVEL } }
      envFrom:
        - configMapRef: { name: app-config }    # all keys as env
      volumeMounts:
        - { name: cfg, mountPath: /etc/app }
  volumes:
    - name: cfg
      configMap:
        name: app-config
        items:                                  # optional: project specific keys
          - { key: app.properties, path: app.properties }
```

---

## ConfigMap — refresh semantics

| Consumption | Refreshes when CM changes? |
|---|---|
| `env` (single key) | ❌ Never. Restart the pod. |
| `envFrom` | ❌ Never. Restart the pod. |
| `volumeMount` (no subPath) | ✅ Yes — kubelet syncs ~every 60s |
| `volumeMount` with `subPath:` | ❌ Never |
| ConfigMap with `immutable: true` | n/a — can't be edited |

**Immutable ConfigMaps** are a perf optimization at scale (apiserver doesn't have to watch them). Set once:

```yaml
data: { ... }
immutable: true
```

---

## Secret — same shape, different storage rules

```yaml
apiVersion: v1
kind: Secret
metadata: { name: db }
type: Opaque                           # generic; other types: kubernetes.io/tls, dockerconfigjson, ...
data:                                  # base64-encoded
  password: c2VjcmV0
stringData:                            # plain text; encoded automatically on write
  username: admin
```

Same three consumption patterns as ConfigMap. **Secret is not encrypted at rest by default** — etcd holds base64. Enable encryption at rest in the apiserver config (`--encryption-provider-config`).

Imperative shortcut:
```sh
k create secret generic db \
  --from-literal=username=admin \
  --from-literal=password=secret
```

---

## Secret types you might see on the exam

| Type | Use |
|---|---|
| `Opaque` | generic key/value (default) |
| `kubernetes.io/tls` | TLS cert+key; for Ingress, webhooks |
| `kubernetes.io/dockerconfigjson` | image pull from private registry (`imagePullSecrets`) |
| `kubernetes.io/service-account-token` | (legacy) auto-mounted SA tokens — projected tokens are the modern path |
| `kubernetes.io/basic-auth`, `ssh-auth` | rarely used directly |

```sh
k create secret tls web-tls --cert=tls.crt --key=tls.key
k create secret docker-registry regcred --docker-server=... --docker-username=... --docker-password=...
```

---

## Probes — the three kinds

| Probe | Kubelet asks | Failure ⇒ |
|---|---|---|
| **liveness** | "Should I still be alive?" | Container is **restarted** |
| **readiness** | "Should I receive traffic?" | Pod is removed from Service **endpoints** (still running) |
| **startup** | "Have I finished booting yet?" | Acts like liveness while it runs; once one success, it deactivates and liveness/readiness take over |

**Startup** exists to handle slow boots without giving liveness a permanent grace period.

---

## Probe handlers — three options

```yaml
livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
    httpHeaders:
      - { name: X-Probe, value: liveness }

readinessProbe:
  tcpSocket:
    port: 5432

startupProbe:
  exec:
    command: ["sh", "-c", "cat /tmp/ready"]
```

Tunables on each:

```yaml
initialDelaySeconds: 0       # wait this long before first probe
periodSeconds: 10            # probe every N seconds
timeoutSeconds: 1            # each probe must respond within
successThreshold: 1          # for readiness only (back to ready after N successes)
failureThreshold: 3          # mark failed after N consecutive failures
```

---

## Probe pitfalls

- **Liveness too aggressive** → restart loops on slow startup. *Fix:* startup probe.
- **No readiness probe** → traffic hits a pod that's not actually ready (still warming caches). Result: bursts of 5xx after rollouts.
- **Liveness == readiness with same command** → during cold start, *all* replicas fail liveness simultaneously, and the Deployment kills them all.
- **`exec` probe with heavy command** → eats CPU + has fork/exec overhead. Prefer `httpGet` when possible.
- **Probe pointing at a different container's port** in a multi-container pod — pods don't share ports semantically per container, but the network namespace IS shared. Be explicit.

---

## init containers

Run **before** regular containers, **in order**, each to completion.

```yaml
spec:
  initContainers:
    - name: wait-db
      image: busybox:1.36
      command: ["sh", "-c", "until nc -z db 5432; do sleep 2; done"]
    - name: migrate
      image: myapp/migrator:1.0
  containers:
    - name: app
      image: myapp:1.0
```

If any init container fails, the pod restarts the init chain.

Use cases: wait for a dependency, fetch config from a vault, run a migration, set kernel sysctls (privileged init).

---

## Pod lifecycle states

```
Pending  → Running ─┬→ Succeeded
                    └→ Failed
                                Unknown   (node lost contact)
```

Pending substates (in `describe`):
- `ContainerCreating` — image pulling, volume mounting
- `ImagePullBackOff` — image name/registry/creds problem
- `CreateContainerConfigError` — referenced ConfigMap/Secret doesn't exist
- `CrashLoopBackOff` — container started then exited; backoff doubles each retry

```sh
k get pods -w
k describe pod <p>          # see events at the bottom
k logs <p> --previous       # logs from the previous crash
```

---

## QoS classes (preview — full coverage Day 3)

The kubelet assigns a QoS class to each pod, based on requests/limits:

| Class | Requirement | Eviction priority |
|---|---|---|
| **Guaranteed** | every container has `requests == limits` for CPU AND memory | last to be evicted |
| **Burstable** | at least one container has requests, but not Guaranteed | middle |
| **BestEffort** | no requests or limits set | **first to be evicted** under pressure |

Production rule of thumb: set both. Guaranteed for latency-sensitive, Burstable for everything else.

---

# Lab 2b — ConfigMaps, Secrets, Probes

→ `trainees/day1/labs/lab2b-config-probes.md`

**45 min.** Inject a ConfigMap as env + as volume. Inject a Secret as env. Add liveness + readiness + startup probes to a deployment. Watch what happens when each fails.

---

## Day 1 wrap-up

You can now:

- Articulate what every control-plane and node component does
- Bring up a 3-node cluster on **v1.35.1** with kind (kind's latest node image)
- Use kubectl fluently (completion + `$do` + `$now`)
- Generate YAML for every workload type imperatively, then edit it
- Inject config via ConfigMap and Secret, three ways
- Wire all three probes correctly

**Tonight (45 min):**
- One [killercoda.com](https://killercoda.com/killer-shell-cka) free scenario
- Re-do Lab 1 from memory, no notes — time yourself

**Tomorrow:** Services, DNS, Ingress, Gateway API, NetworkPolicy.

Sleep eight hours.
