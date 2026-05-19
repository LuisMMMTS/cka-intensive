---
title: CKA Intensive — Trainer Handbook
author: Luis Torres
---

# CKA Intensive — Trainer Handbook

**Use this while presenting.** It's your speaker notes, pacing guide, and
"what to say next" reference, all in one. Trainees never see it.

> If something in the slides or labs surprises you mid-class, the
> corresponding "What you'll hit" notes below should already cover it.

---

## How to use this handbook

- **Read the day's "Pacing" section first thing each morning.** It tells you
  the order of slots, expected duration, and which lab corresponds to which
  block.
- **Each slot has 3 fields:**
  - *Teach* — the one or two points you must land. Skip anything else.
  - *Trainees ask* — questions you will almost always be asked; answer ready.
  - *Watch for* — common stumbles + how to unblock without spoiling the lesson.
- **Pacing slack** is your buffer. If you're behind, see "If you're tight
  on time" at the end of each day.

---

## Universal rules (every day)

- **Day starts at 08:30 sharp.** Latecomers join the second slot; the morning
  quiz on Days 2–4 is non-negotiable.
- **Open with 5 minutes of "yesterday's recap" on Days 2–4** even if the quiz
  covers it. The repetition is doing the work.
- **Labs are the assessment.** You walk the room while trainees work. If
  someone's been stuck for 10+ minutes, sit down with them — don't let pride
  hide a misunderstanding until the mock exam.
- **Resets are not failures.** Trainees should run `lab-clean.sh` between
  unrelated labs and `kind-reset.sh` if something's truly wedged. Build the
  habit early — Day 1 Lab 1 — so it's automatic by Day 4.
- **Type slowly. Narrate every flag.** Resist the muscle memory shortcut.
  Trainees can't read your mind.
- **If a script breaks**, the order of escalation is:
  1. `verify-cluster.sh` — what does it say?
  2. `kubectl get pods -A -o wide` — anything not Running?
  3. Last 30 lines of `journalctl -u kubelet`
  4. `kind-reset.sh` — start over fresh, lose 90 seconds.

---

# Day 1 — Foundations

**Theme:** containers → kubernetes architecture → kubectl fluency → workloads
+ config/secrets/probes. By 17:00 every trainee should be able to imperatively
create any controller type and inject config three ways.

## Pacing

| Slot | Duration | Content | Lab |
|---|---|---|---|
| 08:30–09:30 | 60 min | **Lab 0** — environment bootstrap | lab0 |
| 09:30–10:45 | 75 min | Containers + Kubernetes architecture deep-dive | — |
| 10:45–11:00 | 15 min | Break | — |
| 11:00–12:30 | 90 min | kubectl mastery + **Lab 1** | lab1 |
| 12:30–13:30 | 60 min | Lunch | — |
| 13:30–15:00 | 90 min | Workload types + **Lab 2** | lab2 |
| 15:00–15:15 | 15 min | Break | — |
| 15:15–16:30 | 75 min | ConfigMaps, Secrets, Probes + **Lab 2b** | lab2b |
| 16:30–17:00 | 30 min | Day-1 recap, Day-2 preview, quiz preview | — |

## Slot-by-slot notes

### Lab 0 (08:30–09:30) — environment bootstrap

- *Teach*: trainees run `kind-bootstrap.sh && verify-cluster.sh`. That's it.
  Most of this hour is **debugging individuals** whose VMs missed a setup
  step, not lecturing.
- *Trainees ask*:
  - *"Why does my cluster show v1.35.1 if the course is v1.36?"* → kind
    hasn't shipped a v1.36 node image yet; Days 1-3 are on v1.35.1 (kind),
    Day 4 builds the v1.36.1 kubeadm cluster yourself. README explains.
  - *"Calico install takes 3 minutes — is that normal?"* → yes. The
    tigera-operator pulls images and reconciles CRDs serially.
- *Watch for*:
  - Trainees who skipped the docker primer and don't understand why
    `docker ps` shows their kind nodes. Five-minute aside on container
    runtimes is cheaper than letting them fall behind.
  - VMs where `~/.bashrc` is missing the CKA block (no `k` alias, no `$do`).
    Quick fix: paste the block from `infra/scripts/template-bake.sh`, then
    `source ~/.bashrc`.
  - Anyone whose `verify-cluster.sh` fails the NetworkPolicy check — Calico
    didn't replace kindnet. Make them run `kind-reset.sh` immediately. If
    it still fails, swap them onto a spare VM.

### Containers + architecture (09:30–10:45)

- *Teach*: namespaces, cgroups, control plane components (apiserver, etcd,
  scheduler, controller-manager), node components (kubelet, kube-proxy,
  CRI). **Spend ~10 min on etcd specifically** — origin (CoreOS 2013),
  Raft mechanics, why not Postgres. Slides 294–360 of day1.md cover this;
  follow them.
- *Trainees ask*:
  - *"Where does kube-proxy actually run?"* → DaemonSet, one pod per node,
    programs iptables/IPVS rules from Service/Endpoint state.
  - *"What's the difference between docker and containerd in kind?"* → kind
    nodes run their own containerd; the host docker is just hosting the
    node containers. Two separate runtimes.
  - *"Is Raft the same as Paxos?"* → same guarantees, different design
    goal (Raft prioritized understandability). Don't go deeper unless
    asked.
- *Watch for*: glazed eyes during the request-flow diagram (auth → authz →
  admission → etcd). Slow down — this comes back in Day 3 RBAC.

### Lab 1 (11:00–12:30) — kubectl mastery

- *Teach*: imperative-first. Every workload type can be generated with
  `kubectl create ... $do > file.yaml`. The exam rewards speed; YAML
  editing comes second.
- *Trainees ask*:
  - *"Should I use `kubectl apply` or `kubectl create`?"* → apply for
    everything you'll re-edit (declarative); create for one-shot imperative
    starters that you'll discard.
  - *"What's `$do`?"* → `--dry-run=client -o yaml`. Look at `~/.bashrc`.
- *Watch for*:
  - Trainees who don't know vim. Make them run `vimtutor` at lunch. Not
    optional — the exam uses vim.
  - Anyone scrolling `kubectl get pods --watch` instead of using `-w` once
    and ctrl-C'ing. Show them.

### Lab 2 (13:30–15:00) — workload types

- *Teach*: each controller type's stable identity model (Deployment = ephemeral,
  StatefulSet = stable names, DaemonSet = one-per-node, Job = run-to-completion,
  CronJob = scheduled).
- *Trainees ask*:
  - *"Why does StatefulSet need a headless service?"* → so each pod gets a
    stable DNS name (`pod-0.svc.ns.svc.cluster.local`). Demo by running
    `nslookup db-0.db` from a debug pod.
  - *"Why doesn't `kubectl create daemonset` exist?"* → historical; just
    use `--dry-run=client` on a Deployment and edit `kind: DaemonSet`.
- *Watch for*: trainees skipping the StatefulSet pod-deletion test
  (delete db-1, watch it come back as db-1). That's the lesson. Make them
  do it.

### Lab 2b (15:15–16:30) — ConfigMaps, Secrets, Probes

- *Teach*: three injection patterns (env single key, envFrom all keys,
  volume mount). All three appear on the exam.
- *Trainees ask*:
  - *"Does a ConfigMap update propagate to running pods?"* → only when
    mounted as a volume (refresh ~60s); env vars are baked at pod start.
  - *"Why does the lab explicitly create a `broken-web` deployment for
    section 2b.6?"* → the original "patch readiness on existing web"
    approach doesn't drain endpoints with 3 replicas (maxUnavailable=0
    after rounding); a separate deployment makes the mechanic visible.
- *Watch for*: trainees confused about startup vs readiness vs liveness.
  Whiteboard the timeline: startupProbe gates the other two; liveness
  kills the pod; readiness removes from Service endpoints. Slide deck
  covers it but the verbal walkthrough cements it.

## Day-1 recap (16:30–17:00)

- 5-minute oral round-table: each trainee names one new thing learned.
- Preview Day 2: networking — Services, DNS, Ingress, Gateway API,
  NetworkPolicy.
- Reminder: there's a quiz at 08:30 tomorrow.

## If you're tight on time

- **Skip Lab 2 stretch goals** (rolling-update zero-downtime wget loop).
  The basic creation of each controller is the assessment.
- **Skip the bonus in Lab 2b** (ConfigMap volume update demonstration) —
  fun but not exam-critical.
- **Never skip Lab 0.** A broken cluster at 17:00 means a broken Day 2.

---

# Day 2 — Networking

**Theme:** how packets actually get to pods. ClusterIP / NodePort /
LoadBalancer mechanics, DNS, Ingress, Gateway API, NetworkPolicy with
real enforcement (Calico).

## Pacing

| Slot | Duration | Content | Lab |
|---|---|---|---|
| 08:30–08:40 | 10 min | **Day-1 quiz** (oral) | — |
| 08:40–10:00 | 80 min | Services + DNS deep-dive | — |
| 10:00–10:15 | 15 min | Break | — |
| 10:15–12:00 | 105 min | Ingress + **Lab 3** | lab3 |
| 12:00–13:00 | 60 min | Lunch | — |
| 13:00–14:30 | 90 min | Gateway API + **Lab 3b** | lab3b |
| 14:30–14:45 | 15 min | Break | — |
| 14:45–16:30 | 105 min | NetworkPolicy + **Lab 4** | lab4 |
| 16:30–17:00 | 30 min | Recap, Day-3 preview | — |

## Slot-by-slot notes

### Day-1 quiz (08:30–08:40)

Quick oral round, no slides. Sample questions:
- What does `kubectl rollout undo` actually do? (Switches the Deployment
  back to the previous ReplicaSet.)
- What's in a `kubeconfig`'s context? (Cluster + user + default namespace.)
- Difference between Job and CronJob? (CronJob owns/schedules Jobs.)

### Services + DNS (08:40–10:00)

- *Teach*: ClusterIP is the default; Endpoints (now EndpointSlices) carry
  the actual pod IPs; kube-proxy programs iptables to translate Service IP
  → pod IP. Headless Service (`clusterIP: None`) skips kube-proxy and
  returns pod IPs from DNS directly.
- *Trainees ask*:
  - *"What's an EndpointSlice vs an Endpoint?"* → same thing,
    EndpointSlice is the modern scaling-friendly version. Both exist.
  - *"How does CoreDNS find Services?"* → it watches the apiserver for
    Service/Endpoint objects and serves `*.svc.cluster.local`.
- *Watch for*: confusion about Service IP being virtual. The clusterIP
  isn't bound to any interface — it only exists as iptables rules. Show
  `iptables -t nat -L -n | grep <service-ip>` on a kind node to make it
  concrete.

### Lab 3 + Ingress (10:15–12:00)

- *Teach*: NodePort is the bridge; Ingress is the L7 router; ingress-nginx
  is the concrete controller. The kind cluster maps host:80 → control-plane,
  so curling `http://localhost` with the right Host header reaches the
  Ingress.
- *Trainees ask*:
  - *"Why do I need to set Host header in curl?"* → host-based routing.
    The Ingress matches on Host; without it, ingress-nginx falls through
    to its default backend (404).
  - *"What's the difference between Ingress and Service type=LoadBalancer?"*
    → Service LB is L4 (one VIP per Service, one cloud LB each); Ingress
    is L7 (one controller serves many hostnames, much cheaper).
- *Watch for*:
  - First-time ingress-nginx install on every trainee's cluster simultaneously
    can hammer the WiFi. If you're on a constrained connection, install
    ingress-nginx once on the trainer cluster ahead of time and have
    trainees follow along on the projected screen instead.
  - The admission webhook race: applying an Ingress immediately after
    `kubectl apply -f deploy.yaml` for ingress-nginx fails with "connection
    refused" because the webhook service isn't ready yet. Tell trainees to
    wait ~30s after the controller pod is Ready before applying the Ingress.

### Lab 3b — Gateway API (13:00–14:30)

- *Teach*: Gateway API is the next-gen replacement for Ingress. Three
  resource types: GatewayClass (chosen-by-admin), Gateway (chosen-by-cluster-operator),
  HTTPRoute (chosen-by-app-team). Cleaner separation of concerns.
- *Trainees ask*:
  - *"Should I use Ingress or Gateway API?"* → both are CKA-relevant in
    2026 curriculum. Ingress is widely deployed today; Gateway API is the
    direction. Know both.
  - *"What's Contour?"* → one of the Gateway API controllers (Envoy under
    the hood). We pre-installed it; trainees don't install it themselves
    today.
- *Watch for*: the trainer has to pre-install Contour + Gateway API CRDs
  before this lab. If you forgot, `lab3b-gateway-api.sh` smoke test will
  detect it. Skip the lab and apologize if so.

### NetworkPolicy + Lab 4 (14:45–16:30)

- *Teach*: NetworkPolicy is a deny-by-default mechanism. **The CNI must
  support enforcement** — kindnet does NOT. We replaced it with Calico
  during bootstrap. Two policy types: Ingress (who can talk to me) and
  Egress (who can I talk to). AND-within-selector, OR-between-selectors —
  this is the #1 trap.
- *Trainees ask*:
  - *"Why doesn't my deny-all policy block external traffic?"* → it does,
    but it's targeting Ingress only. Add `policyTypes: [Ingress, Egress]`
    for both directions.
  - *"Are NetworkPolicies stateful?"* → yes — response traffic for an
    allowed inbound connection is automatically allowed back.
- *Watch for*:
  - The AND/OR trap. If a trainee writes `from: [{podSelector}, {namespaceSelector}]`
    expecting both to match, they got OR. To get AND, use a single
    `from:` entry with both selectors INSIDE it. Slide deck has the diagram.
  - Trainees expecting NetworkPolicy to enforce immediately. Calico has
    ~3-5s programming delay for new policies. Tell them this so they
    don't burn time debugging.

## Day-2 recap (16:30–17:00)

- Quick round on the AND/OR trap (verify everyone got it).
- Preview Day 3: scheduling, storage, RBAC, then the new 2024 curriculum
  trio (Helm, Kustomize, HPA), plus PSA.

## If you're tight on time

- **Skip Gateway API header-routing portion of Lab 3b** — the 80/20 split
  is the assessable behavior.
- **Skip the namespaceSelector portion of Lab 4** — podSelector + ingress
  rule is what the exam tests.
- **Never skip the AND/OR trap.** Make trainees write a multi-selector
  policy by hand on paper. It's the most exam-critical concept of Day 2.

---

# Day 3 — Cluster ops

**Theme:** the longest day. Scheduling, storage, RBAC, **Helm + Kustomize
+ HPA (new in 2024 curriculum)**, PSA. By 17:00 every trainee should be
able to RBAC-restrict a namespace, install/upgrade/rollback a Helm chart,
and explain why their HPA isn't scaling.

## Pacing

| Slot | Duration | Content | Lab |
|---|---|---|---|
| 08:30–08:40 | 10 min | **Day-2 quiz** | — |
| 08:40–09:45 | 65 min | Scheduling + **Lab 6** (taints/affinity) | lab6 |
| 09:45–10:30 | 45 min | Storage + **Lab 5** | lab5 |
| 10:30–10:45 | 15 min | Break | — |
| 10:45–11:30 | 45 min | ResourceQuota + LimitRange + **Lab 5b** | lab5b |
| 11:30–12:30 | 60 min | RBAC + **Lab 6b** | lab6b |
| 12:30–13:30 | 60 min | Lunch | — |
| 13:30–14:00 | 30 min | Helm + **Lab 6c** | lab6c |
| 14:00–14:30 | 30 min | Kustomize + **Lab 6d** | lab6d |
| 14:30–14:45 | 15 min | Break | — |
| 14:45–15:30 | 45 min | HPA + **Lab 6e** | lab6e |
| 15:30–16:00 | 30 min | PSA + **Lab 6f** | lab6f |
| 16:00–17:00 | 60 min | Day-3 catch-up + Day-4 preview | — |

## Slot-by-slot notes

### Scheduling + Lab 6 (08:40–09:45)

- *Teach*: nodeSelector (simple equality), taints/tolerations (node opt-out),
  nodeAffinity (required vs preferred). Resource requests are the scheduler's
  primary input — limits are the kubelet's enforcement, not the scheduler's.
- *Trainees ask*:
  - *"What's the difference between taint NoSchedule and NoExecute?"* →
    NoSchedule blocks new pods; NoExecute also evicts running pods that
    don't tolerate it.
  - *"When would I use preferred vs required?"* → required = hard
    constraint, pod stays Pending if no node matches; preferred = soft,
    scheduler scores nodes and picks best fit.
- *Watch for*: trainees forgetting to untaint at end of lab. Lab text
  reminds them but they skip. Make untainting part of the Deliverable check.

### Storage + Lab 5 (09:45–10:30)

- *Teach*: StorageClass = how PVs get provisioned. PVC = claim by app.
  PV = actual storage object. Dynamic provisioning binds PVC → freshly-created PV.
  Reclaim policy controls what happens when PVC is deleted (Retain keeps
  the PV; Delete nukes it).
- *Trainees ask*:
  - *"Why does my PVC stay Pending?"* → either no matching StorageClass, or
    no PV exists that satisfies the request. `kubectl describe pvc` shows
    why.
  - *"What's `accessModes: ReadWriteOnce`?"* → one node can mount it
    read/write. Not "one pod" — multiple pods on the same node share it.
- *Watch for*: confusion about hostPath PVs being node-local. If a pod
  with a hostPath PV is rescheduled to a different node, the data is gone.
  Mention this; it's the conceptual setup for "why we need a real CSI
  driver in production."

### ResourceQuota + LimitRange + Lab 5b (10:45–11:30)

- *Teach*: ResourceQuota is namespace-level (caps totals). LimitRange is
  per-pod defaults (so trainees don't have to write requests/limits every
  time). **Quotas force pods to declare what they're tracking** — once
  you quota `requests.cpu`, every pod in the namespace MUST set `requests.cpu`.
- *Trainees ask*:
  - *"Why doesn't my deployment scale up after I add quota?"* → because
    the new pods don't declare requests. Either: (a) add requests to the
    deployment spec, or (b) add a LimitRange to inject defaults.
- *Watch for*: pod count caps (`pods: "5"`) silently capping replica
  scale-ups. The ReplicaSet shows "exceeded quota" events; teach trainees
  to look there.

### RBAC + Lab 6b (11:30–12:30)

- *Teach*: 4 building blocks — Role/ClusterRole (what), RoleBinding/ClusterRoleBinding
  (who). The bind direction matters: RoleBinding can refer to a ClusterRole
  (and scope it to one namespace). Use this to reuse the built-in `edit`
  ClusterRole in just one namespace.
- *Trainees ask*:
  - *"What's a ServiceAccount?"* → a non-human identity for pods. Each
    pod gets a token mounted at `/var/run/secrets/kubernetes.io/serviceaccount/token`.
  - *"Why does `auth can-i` always return yes for me?"* → because you're
    cluster-admin. Use `--as=system:serviceaccount:ns:sa-name` to test
    a specific SA's perms.
- *Watch for*: trainees confusing user accounts with ServiceAccounts.
  Users are external (cert/token-issued); SAs are namespace-scoped
  Kubernetes objects.

### Helm + Lab 6c (13:30–14:00)

- *Teach*: chart = templated YAML. `helm install` renders + applies.
  `--reuse-values` on upgrade preserves your prior `--set` overrides
  (forget this and your replicaCount resets). Rollback is by revision
  number, NOT by chart version.
- *Trainees ask*:
  - *"What version of Helm is this?"* → v4.2.0. Pre-installed in the bake.
    Tiller is long-gone; Helm talks directly to apiserver.
  - *"Where do values come from?"* → in order of precedence: `--set` > 
    `-f values.yaml` > chart default `values.yaml`. Later overrides win.
- *Watch for*: trainees expecting `helm install` to be idempotent. It's
  not — second run errors with "release exists." Use `helm upgrade --install`
  for CI-safe idempotency.

### Kustomize + Lab 6d (14:00–14:30)

- *Teach*: `kubectl apply -k` is built in (no separate tool needed).
  Base = generic manifest. Overlays = patches per environment. `images:`
  patches container images; `patches:` does structured JSON patch.
  `configMapGenerator:` produces hash-suffixed ConfigMaps for immutable
  releases (rolling update triggers when the hash changes).
- *Trainees ask*:
  - *"Helm vs Kustomize — which should I use?"* → Helm for distributed/third-party
    charts (bitnami, prometheus). Kustomize for your own manifests where
    you don't need templating, just patches per environment.
- *Watch for*: the `commonLabels` field is deprecated; you'll see a
  warning. The replacement is `labels:`. Lab text uses the deprecated
  form intentionally so trainees see the warning — it's good exposure.

### HPA + Lab 6e (14:45–15:30)

- *Teach*: HPA needs metrics-server (already installed) AND resource
  requests on the target pod (without requests, no utilization to
  compute). HPA v2 supports multiple metrics — it scales to satisfy
  whichever demands more replicas. **Scale-down has a 5-minute
  stabilization window** by default to avoid bouncing.
- *Trainees ask*:
  - *"Why is my HPA TARGETS showing `<unknown>`?"* → metrics-server hasn't
    scraped yet. Wait 30-60s.
  - *"Why isn't my HPA scaling up under load?"* → most common: no
    requests on the pod (no denominator for CPU%). Second-most: load
    isn't actually hitting the pods (Service routing).
- *Watch for*: in the kind cluster, the load test from `hey` often
  doesn't produce enough CPU pressure to trigger scale-up. If trainees
  hit this, it's not a bug — nginx is too efficient. Discuss what
  they'd do in production (better load tool, lower CPU target,
  realistic workload).

### PSA + Lab 6f (15:30–16:00)

- *Teach*: Pod Security Admission is namespace-level. Three modes —
  enforce (block), warn (warn user), audit (log to audit log). Three
  levels — privileged (anything), baseline (no host*), restricted
  (locked down). On the exam, you'll see "create a Pod in this namespace"
  where the namespace has `enforce=restricted`. Know the 4 required
  fields cold: `runAsNonRoot`, `seccompProfile=RuntimeDefault`,
  `allowPrivilegeEscalation=false`, `capabilities.drop=[ALL]`.
- *Trainees ask*:
  - *"What if my image runs as root?"* → use a non-root variant
    (`nginxinc/nginx-unprivileged`) or override `runAsUser` to a
    non-zero UID.
  - *"What goes wrong with `readOnlyRootFilesystem: true`?"* → app crashes
    when it tries to write. Add emptyDir mounts for every path it writes
    to (`/var/cache/nginx`, `/var/run`, `/tmp` for nginx).
- *Watch for*: trainees who only mount `/var/cache/nginx` and `/var/run`
  and wonder why nginx-unprivileged still crashes. Lab text now includes
  `/tmp` (fixed bug). If a trainee has an old lab cached, point them
  at the current version.

## Day-3 recap (16:00–17:00)

- This is a long day; use the catch-up time for trainees who fell behind
  on Helm/HPA. Walk the room.
- Preview Day 4: kubeadm cluster build from scratch, etcd backup/restore,
  CRDs, troubleshooting, mock exam. **Tomorrow you delete your kind
  cluster** and build a real kubeadm cluster on your VM.

## If you're tight on time

- **Skip Lab 6d configMapGenerator section** (6d.6) — the hash-suffix
  pattern is good knowledge but not exam-tested.
- **Skip the HPA memory metric** (6e.6) — single CPU metric is the exam.
- **Never skip PSA Lab 6f.** It's 5% of the exam.

---

# Day 4 — Cluster lifecycle + exam prep

**Theme:** build a kubeadm cluster, recover from disasters, learn the
troubleshooting playbook, then sit a mock. Today is where trainees prove
they can pass the real exam.

## Pacing

| Slot | Duration | Content | Lab |
|---|---|---|---|
| 08:30–08:40 | 10 min | **Day-3 quiz** | — |
| 08:40–10:30 | 110 min | kubeadm cluster install + **Lab 7** | lab7 |
| 10:30–10:45 | 15 min | Break | — |
| 10:45–11:30 | 45 min | TLS certs deep-dive | — |
| 11:30–12:30 | 60 min | etcd backup/restore + **Lab 8** | lab8 |
| 12:30–13:30 | 60 min | Lunch | — |
| 13:30–14:15 | 45 min | CRDs + **Lab 8b** | lab8b |
| 14:15–15:00 | 45 min | Troubleshooting playbook + **Lab 9** | lab9 |
| 15:00–15:15 | 15 min | Break | — |
| 15:15–16:30 | 75 min | **Mock exam** (75 min, 15 questions) | mock-exam |
| 16:30–17:00 | 30 min | Mock debrief + exam logistics | — |

## Slot-by-slot notes

### Lab 7 — kubeadm install (08:40–10:30)

- *Teach*: this is the longest single lab of the course. Trainees go from
  bare Debian VM (with kubelet/kubeadm/kubectl already apt-installed by
  the bake) to a single-node cluster they can `kubectl get nodes` against.
  Prereqs first (swap, kernel modules, sysctls, containerd cgroup driver),
  then `kubeadm init`, then CNI (Calico v3.28.0 manifest for simplicity),
  then untaint the control-plane so workloads can land.
- *Trainees ask*:
  - *"Why do we need to disable swap?"* → kubelet refuses to start if
    swap is on (kubeadm 1.22+ allowed it via feature gate; 1.28+ requires
    explicit opt-in). Easier to disable.
  - *"What's the SystemdCgroup setting?"* → containerd's cgroup driver.
    Must match kubelet's (both systemd, the default since 1.22).
- *Watch for*:
  - The CRI error: `unknown service runtime.v1.RuntimeService`. Always
    means containerd's CRI plugin is disabled or configured wrong. Fix:
    `containerd config default > /etc/containerd/config.toml` and restart.
  - Trainees forgetting to untaint the control-plane. Their pods will
    sit Pending. `kubectl taint node <name> node-role.kubernetes.io/control-plane:NoSchedule-`.

### TLS certs (10:45–11:30)

- *Teach*: kubeadm generates 3 CAs (kubernetes-ca, etcd-ca, front-proxy-ca)
  and ~10 leaf certs. CAs live 10 years; leaf certs 1 year.
  `kubeadm certs check-expiration` shows everything. `kubeadm certs renew all`
  refreshes leaves; CAs require manual rotation.
- *Trainees ask*:
  - *"What happens when the CA expires?"* → cluster dies. Plan ahead.
  - *"Does kubeadm auto-rotate?"* → leaf certs auto-rotate on `kubeadm upgrade`.
    Otherwise manual.
- *Watch for*: the cert paths (`/etc/kubernetes/pki/`). Make trainees
  `ls -la` it so they see the layout. The etcd subdirectory is separate.

### etcd backup + Lab 8 (11:30–12:30)

- *Teach*: `etcdctl snapshot save` writes a binary file. `etcdctl snapshot
  restore` writes to a new data-dir (NOT in-place). To activate, point the
  etcd static pod manifest at the new data-dir. **This is high-frequency
  exam content** — memorize the commands cold.
- *Trainees ask*:
  - *"Why do we need ETCDCTL_API=3?"* → v2 API is deprecated. Always 3.
  - *"What about etcd member health?"* → `etcdctl endpoint health` and
    `etcdctl member list`. Useful for multi-member etcd, less so for our
    single-node lab.
- *Watch for*:
  - The cert flag explosion (`--cacert`, `--cert`, `--key`). Cheatsheet
    has them all. Make trainees copy/paste from there.
  - File permissions: `/var/lib/etcd-restore` must be owned by etcd user
    (UID/GID 0 in the kubeadm setup — the static pod runs as root).

### CRDs + Lab 8b (13:30–14:15)

- *Teach*: a CRD defines a new resource type. A controller (separate
  component, often a Deployment) watches CR instances and reconciles them
  against the world. Same control loop as built-in resources.
- *Trainees ask*:
  - *"What's the difference between a CRD and an Operator?"* → CRD is the
    schema. Operator = CRD + controller logic. cert-manager has both.
  - *"What happens if I delete the controller?"* → reconciliation stops.
    Existing resources keep running; new CRs don't get reconciled.
- *Watch for*: trainees getting confused that `kubectl get certificates`
  works after the CRD is installed but BEFORE the controller is running.
  That's the lesson: the API surface and the reconciliation are decoupled.

### Troubleshooting + Lab 9 (14:15–15:00)

- *Teach*: the playbook is the slide. **Always start with `kubectl get pods -A -o wide`** —
  it tells you 80% of the answer (what's not Running, on what node). Then
  `kubectl describe` for events, then `kubectl logs` for app output, then
  `journalctl -u kubelet` if the kubelet itself is sick.
- *Watch for*: Lab 9 is intentionally hard. Trainees may stall at 20+ min
  per scenario. Hint timing: 10 min in, suggest "check kubelet status
  on the affected node." 15 min in, point at `systemctl status kubelet`.
  20 min in, just walk them through it — the exam time pressure won't
  wait for breakthroughs.

### Mock exam (15:15–16:30)

- **75 minutes, 15 questions.** Exam conditions: kubernetes.io/docs,
  helm.sh/docs, kubernetes.io/blog tabs only — close everything else.
  No talking. No internet outside the allowlist.
- *You*: sit at the front, watch the clock, don't help. The point is they
  experience the time pressure.
- At T-15 minutes remaining, give a verbal 15-min warning. At T-0, hard stop.

### Debrief (16:30–17:00)

- Walk through the answer to each mock question, focusing on the time-saving
  shortcuts (e.g., `$do` to generate YAML, `--from-literal` for Secrets/CMs).
- Discuss the real exam: 2 hours, ~17 questions, performance-based, +1 hour
  retake allowed if you fail. Killer.sh comes with two exam-sim sessions —
  do both before booking.
- Send-off: every trainee gets one specific recommendation from you on what
  to drill next week before booking.

## If you're tight on time

- **Skip the cert deep-dive in slot 3** (compress to 15 minutes). Lab 8
  exercises the muscle anyway.
- **Skip Lab 8b stretch goals.** The cert-manager install + Certificate
  resource is enough.
- **Never skip the mock exam.** It's the assessment for the whole course.

---

# Emergency procedures

## A trainee's cluster is wedged

1. `verify-cluster.sh` — does it tell you what's wrong?
2. `kind delete cluster --name cka && kind-bootstrap.sh` — 90 seconds,
   start over. Their lab progress is gone but their VM state is intact.
3. If their VM itself is broken (disk, fs, network) — swap to a spare
   replica.

## You're 30+ minutes behind

- Skip the "stretch" and "bonus" portions of upcoming labs (every lab has
  them, they're optional).
- Trim the lecture for the next major slot from 60 min → 30 min by
  focusing only on the exam-tested portion.
- **Never compress the mock exam.** It must be the full 75 minutes.

## A trainee is way ahead

- Hand them the lab's "stretch" goals.
- Have them re-do the previous lab from imperative-only (no YAML files).
- For Day 3+, give them killer.sh free quiz questions to chew on.

## Course-day quiz questions (Days 2-4)

You can rotate from these:

**Day 2 (Day 1 content):**
- Three components of the control plane that watch the apiserver. (scheduler,
  controller-manager, kubelet via apiserver too)
- What's `imagePullPolicy: Always` vs `IfNotPresent`?
- Difference between an env-var ConfigMap reference and a volume mount?

**Day 3 (Day 2 content):**
- Why does a Service ClusterIP not appear on any interface?
- Default behavior when no NetworkPolicy exists?
- Headless service vs ClusterIP: when?

**Day 4 (Day 3 content):**
- `--reuse-values` on `helm upgrade` — what does it do?
- Why does an HPA show `<unknown>` for TARGETS?
- PSA `restricted` — 4 required fields per container.

---

# Quick-reference: where things live

| Need | Path |
|---|---|
| Slides | `trainees/slides/day{1,2,3,4}.md` |
| Labs | `trainees/day{1,2,3,4}/labs/*.md` |
| Setup walkthrough | `trainees/vm-setup.md` |
| Cheatsheet (let trainees keep this open) | `trainees/cheatsheet.md` |
| Reset between labs | `trainees/lab-reset.md` |
| Mock exam | `trainees/day4/labs/mock-exam.md` |
| Cluster bootstrap | `infra/scripts/kind-bootstrap.sh` |
| Reset cluster | `infra/scripts/kind-reset.sh` |
| Reset labs only | `infra/scripts/lab-clean.sh` |
| Cluster sanity check | `infra/scripts/verify-cluster.sh` |
| VM sanity check | `infra/scripts/verify-template.sh` |
| Re-run all lab tests | `./infra/tests/run-all-labs.sh` |

End of handbook. Good luck.
