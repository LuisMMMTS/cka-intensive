# CKA Intensive — 4-Day Training (Trainee Materials)

A 4-day, hands-on Certified Kubernetes Administrator (CKA) training course
targeting **Kubernetes v1.32**. This repo contains everything trainees see:
labs, slides, primers, reference sheets, and the platform scripts that
build the per-trainee Kubernetes cluster.

Trainer: [Luis Torres](mailto:ltorres@kevel.com)

> **Trainers**: the trainer-only material (schedule, day-by-day word-for-word
> scripts, lab solutions, Lab-9 break/fix scripts) lives in a separate
> **private** repo: [`cka-intensive-trainer`](https://github.com/LuisMMMTS/cka-intensive-trainer).

---

## What's in this repo

```
.
├── trainees/                    ← what you read during the course
│   ├── README.md                 ← course overview
│   ├── pre-course-setup.md       ← REQUIRED before Day 1
│   ├── docker-primer.md          ← mandatory pre-course Docker primer (2-3h)
│   ├── linux-primer.md           ← mandatory pre-course Linux primer (1-2h)
│   ├── vm-setup.md               ← Day-1-morning cluster bootstrap walkthrough
│   ├── lab-reset.md              ← inter-lab reset decision tree
│   ├── cheatsheet.md             ← 1-pager exam survival kit
│   ├── resources.md              ← further-study links
│   ├── day1/  day2/  day3/  day4/   ← 18+ hands-on labs
│   └── slides/                   ← Marp markdown + exported PDFs
└── infra/scripts/                ← what you run on your VM
    ├── template-bake.sh          ← TRAINER-ONLY (you'll never run this)
    ├── kind-bootstrap.sh         ← creates the 3-node kind cluster
    ├── kind-reset.sh             ← full rebuild ~90s
    ├── lab-clean.sh              ← soft cleanup between labs ~5s
    ├── verify-cluster.sh         ← 14-check cluster sanity
    ├── verify-template.sh        ← 30+ check machine sanity
    └── preload-images.sh         ← pre-pull lab images into kind nodes
```

---

## Course-day overview

| Day | Theme | Labs |
|---|---|---|
| 1 | Containers from scratch, architecture deep-dive, kubectl, workloads, ConfigMap/Secret, probes | lab0, lab1, lab2, lab2b |
| 2 | Services, DNS, Ingress, Gateway API, NetworkPolicy + CNI internals | lab3, lab3b, lab4 |
| 3 | Scheduling, storage, RBAC, **Pod Security + immutable infra**, Helm, Kustomize, HPA | lab5, lab5b, lab6, lab6b, lab6c, lab6d, lab6e, lab6f |
| 4 | kubeadm, **edge/lightweight K8s (k3s)**, TLS certs, etcd, CRDs, troubleshooting, mock | lab7, lab8, lab8b, lab9, mock-exam |

CKA curriculum weights this defends against:

| Domain | Weight |
|---|---:|
| Cluster Architecture, Install & Config | 25% |
| Workloads & Scheduling | 15% |
| Services & Networking | 20% |
| Storage | 10% |
| **Troubleshooting** | **30%** |

---

## How the labs run

Each trainee gets a **Debian 13 VM** with everything pre-installed (Docker,
kubectl, helm, kind, kubeadm tooling, VS Code, the course repo, pre-pulled
images). Days 1-3 use a **3-node kind cluster** running on that VM. Day 4
deletes the kind cluster and runs `kubeadm init` on the VM directly for the
real kubeadm/etcd/troubleshooting experience.

Two-tier reset model:

| Tier | Cost | Used for |
|---|---|---|
| `./lab-clean.sh`     | ~5s  | 90% of lab-to-lab transitions |
| `./kind-reset.sh`    | ~90s | Cluster wedged, before Lab 9, etc. |

See [`trainees/vm-setup.md`](./trainees/vm-setup.md) for the full setup
walkthrough and [`trainees/lab-reset.md`](./trainees/lab-reset.md) for the
inter-lab decision tree.

---

## Before Day 1 (mandatory pre-work)

Trainees must complete, in order:

1. [`trainees/pre-course-setup.md`](./trainees/pre-course-setup.md) — connect to your assigned VM, confirm the pre-installed tooling
2. [`trainees/docker-primer.md`](./trainees/docker-primer.md) — what a container actually is (2-3h)
3. [`trainees/linux-primer.md`](./trainees/linux-primer.md) — systemd, journalctl, vim survival (1-2h)
4. `vimtutor` — 30 minutes; the exam uses vim

---

## License

MIT. See [LICENSE](./LICENSE).

You're welcome to use, fork, and adapt this for your own training. If you
do, a link back to the upstream is appreciated but not required.
