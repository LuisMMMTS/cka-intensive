# CKA Intensive — 4 Days

Welcome. This repo is your handbook for the course and your reference afterwards.

**Target Kubernetes version:** v1.32 (current stable as of May 2026).

## How the course runs

- **4 days, ~08:30–17:00** with 1h lunch and two 15-min breaks.
- ~55% hands-on labs, ~45% lecture. The exam is performance-based — typing is what passes you.
- Mornings of Days 2/3/4 start with a **10-min oral quiz** on the previous day's content.
- Bring your laptop charger. You will need it.

## Day-by-day at a glance

| Day | Theme | Highlights |
|---|---|---|
| 1 | Foundations | Architecture, kubectl, workloads, ConfigMaps/Secrets, probes |
| 2 | Networking | Services, DNS, Ingress, Gateway API, NetworkPolicy |
| 3 | Cluster ops | Scheduling, storage, quotas, RBAC, **Helm, Kustomize, HPA** |
| 4 | Lifecycle + Exam | kubeadm, TLS certs, etcd, CRDs/operators, troubleshooting, **mock exam** |

## Before Day 1 (required)

Three things, in this order:

1. [`pre-course-setup.md`](./pre-course-setup.md) — connect to your assigned Debian VM, confirm pre-installed tools work
2. [`docker-primer.md`](./docker-primer.md) — what a container actually is (2-3 h, mandatory)
3. [`linux-primer.md`](./linux-primer.md) — systemd, journalctl, vim survival (1-2 h)

If you arrive on Day 1 without these done, you'll spend the first 2 hours catching up instead of learning. **The course assumes you understand containers conceptually**; we don't re-teach Docker from scratch in the room.

## Day 1 morning

Open [`vm-setup.md`](./vm-setup.md) and follow it during Lab 0. Bootstrapping
the cluster (one kind command) is the first thing you do in class.

## During the course

- Each day's folder (`day1/`, `day2/`, `day3/`, `day4/`) contains its labs.
- Between labs: see [`lab-reset.md`](./lab-reset.md). The cluster has snapshots; resets are fast.
- Solutions are released after each lab is complete — try first, peek second.
- Keep your own notes; you can keep this repo after the course.

## Reference materials

- [`cheatsheet.md`](./cheatsheet.md) — one-page exam survival kit
- [`resources.md`](./resources.md) — official docs, killer.sh, books, podcasts
- [`vm-setup.md`](./vm-setup.md) — Multipass cluster setup walkthrough
- [`lab-reset.md`](./lab-reset.md) — how to reset between labs (fast)

## Exam logistics quick reference

- **Format:** 2 hours, ~15–20 hands-on tasks, performance-based
- **Pass:** 66% (lowered from 74% in 2024)
- **Cost:** ~$395 USD (one free retake within 12 months)
- **Allowed during exam:** `kubernetes.io/docs`, `kubernetes.io/blog`, `helm.sh/docs`
- **Validity:** 2 years
- **Includes:** 2 sessions of [killer.sh](https://killer.sh) simulator (use them both)
- **Curriculum domains and weights:**
  - Cluster Architecture, Install & Config — 25%
  - Workloads & Scheduling — 15%
  - Services & Networking — 20%
  - Storage — 10%
  - **Troubleshooting — 30%**
