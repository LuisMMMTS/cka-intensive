# Resetting Between Labs

You'll run 18+ labs across 4 days. To stay fast, pick the right reset for
each transition. There are only **two tiers** with kind — the cluster is
cheap enough to rebuild that we don't bother with snapshots.

```
┌──────────────────────────────────────────────────────────────────────┐
│  Tier 1 — Soft clean     ~5  s    ./lab-clean.sh                     │
│  Tier 2 — Full rebuild   ~90 s    ./kind-reset.sh                    │
└──────────────────────────────────────────────────────────────────────┘
```

**Default to Tier 1.** Escalate to Tier 2 only when the cluster's
control plane is broken or you've installed cluster-wide things that
conflict with the next lab.

---

## Decision tree

```
Are kube-system pods all Running?                       no ──▶ Tier 2
  │ yes
  ▼
Did this lab modify control-plane files / break the
  kubelet / restore etcd?                              yes ──▶ Tier 2
  │ no
  ▼
Did this lab install something cluster-wide
  (Contour, ingress-nginx, cert-manager, a CRD)?       yes ──▶ Tier 1 + uninstall;
  │ no                                                          Tier 2 if uninstall is messy
  ▼
Tier 1 (just delete the user namespaces).
```

---

## Lab-by-lab guidance

| Just finished | Reset before next lab | Why |
|---|---|---|
| Lab 0 (env)         | — (this *is* the bootstrap) | — |
| Lab 1 (kubectl)     | Tier 1 | Lab deletes `lab1` ns at the end anyway |
| Lab 2 (workloads)   | Tier 1 | Namespace-scoped only |
| Lab 2b (config + probes) | Tier 1 | Namespace-scoped only |
| **Day 1 → Day 2**   | Tier 1 + stop Docker overnight to save battery | — |
| Lab 3 (services)    | Tier 1 (keep ingress-nginx if running Lab 3b) | Ingress controller is reusable |
| Lab 3b (Gateway API) | Tier 1 | Contour + CRDs can stay |
| **Lab 4 (NetworkPolicy)** | Tier 1 | Calico is already the CNI; nothing to rebuild |
| **Day 2 → Day 3**   | Tier 1 + Docker stop | — |
| Lab 5 (storage)     | Tier 1 + `./lab-clean.sh` cleans orphan Retain PVs | — |
| Lab 5b (quotas)     | Tier 1 | — |
| Lab 6 (scheduling)  | Tier 1 + **untaint nodes** (lab tells you to) | A leftover taint haunts every subsequent scheduling test |
| Lab 6b (RBAC)       | Tier 1 + lab-clean handles cluster-scoped role/binding | — |
| Lab 6c (Helm)       | Tier 1 (lab-clean runs `helm uninstall` first) | — |
| Lab 6d (Kustomize)  | Tier 1 | Namespace-scoped |
| Lab 6e (HPA)        | Tier 1 — leave metrics-server installed | metrics-server lives in `kube-system`; not touched by Tier 1 |
| Lab 6f (PSA)        | Tier 1 | Just labels on namespaces |
| **Day 3 → Day 4**   | **Tier 2** | Days 1–3 left CRDs/operators that confuse Day 4 labs |
| **Before Lab 7 (kubeadm)** | **DELETE kind cluster entirely** (`kind delete cluster --name cka`) | Lab 7 is different — you run kubeadm on the Debian VM itself, not in kind. See lab brief. |
| **After Lab 7**     | Either: `kubeadm reset` on the Debian + `./kind-bootstrap.sh` (back to kind for Labs 8/8b/9), OR keep going on the kubeadm-on-Debian cluster (single-node, works for Labs 8/8b). Trainer will guide. | Single-node kubeadm cluster works for Lab 8 (etcd) and 8b (CRDs). |
| **After Lab 8 (etcd)** | Stay on whichever cluster you're on | etcd restore left the cluster healthy; no need to rebuild |
| Lab 8b (CRDs)       | Tier 1 + the lab's `kubectl delete -f cert-manager.yaml` | — |
| **Lab 9 (troubleshooting)** | **Tier 2** | Trainer broke something. The clean way back is to rebuild. |
| Before mock exam    | Tier 2 | Start the exam on clean ground |

---

## Day 4 special — the kubeadm pivot

Day 4 has a distinct shape compared to Days 1-3 because Lab 7 needs you to
run `kubeadm init` yourself. You can't do that *inside* a kind cluster
(kind already ran it for you, in a hidden way). So:

**Day 4 morning, before Lab 7:**

```sh
# delete the kind cluster
kind delete cluster --name cka

# (the lab brief walks you through kubeadm init on the Debian VM directly)
```

**After Lab 7**, you're left with a single-node Kubernetes cluster running
**directly on your Debian VM**, with kubeadm. This cluster works for:

- Lab 8 (etcd backup/restore) — etcd is single-node here, but the snapshot
  commands are identical to a HA cluster.
- Lab 8b (CRDs) — works on any cluster.
- Lab 9 (troubleshooting) — scenarios A/B/C/D all work on a single-node
  cluster; the trainer adjusts the scenario script accordingly.
- Mock exam — runs against your single-node cluster.

If the kubeadm cluster gets too messy, reset:

```sh
sudo kubeadm reset --force
sudo rm -rf /etc/kubernetes /var/lib/etcd ~/.kube/config
# then re-run kubeadm init per Lab 7 brief
```

Or, if you want a **multi-node** cluster back (e.g., to redo the day's
practice):

```sh
sudo kubeadm reset --force
sudo rm -rf /etc/kubernetes /var/lib/etcd ~/.kube/config
./kind-bootstrap.sh
```

---

## End-of-day shutdown

Every evening:

```sh
# Option A — just stop the containers (state preserved)
docker stop cka-control-plane cka-worker cka-worker2

# Option B — delete the cluster entirely (rebuild tomorrow)
kind delete cluster --name cka
```

Option A is cheaper if you'll start tomorrow; option B if you want a fresh
start.

Next morning:

```sh
# Option A continuation
docker start cka-control-plane cka-worker cka-worker2
# wait ~30s for kubelet to settle
kubectl get nodes

# Option B continuation
./kind-bootstrap.sh
```

---

## When all else fails

```sh
./kind-bootstrap.sh --rebuild
./verify-cluster.sh
```

90 seconds. Use this if Tier 2 fails to recover.
