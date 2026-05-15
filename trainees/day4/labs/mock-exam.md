# Mock Exam — 75 Minutes, 15 Tasks

**Rules (mimic the real exam):**
- **75 minutes hard stop.** Set a timer. When time is up, hands off the keyboard.
- Allowed reference: only `kubernetes.io/docs`, `helm.sh/docs`, `kubernetes.io/blog`. No Google, no AI, no peer help.
- Use one terminal window. No copy-paste from the lab solutions or this course's notes.
- Each question states the namespace and cluster context. **Switch before solving.**
- Mark difficulty as you go: ★ easy, ★★ medium, ★★★ hard. Do easy first.

---

## Q1 (4%) — Context

Switch to context `cka` and namespace `q1`. Confirm with `kubectl config view --minify`.

## Q2 (6%) — Multi-container pod with shared volume

In ns `q2`, create a Pod `pair` with two containers:
- `writer`: `busybox:1.36`, command `sh -c 'while true; do date >> /shared/log; sleep 5; done'`
- `reader`: `busybox:1.36`, command `sh -c 'tail -f /shared/log'`

Both mount an `emptyDir` at `/shared`.

## Q3 (6%) — Deployment + service

In ns `q3`, create deployment `web` (3× `nginx:1.27`) and a ClusterIP Service `web` on port 80. Verify endpoints are populated.

## Q4 (5%) — Rolling update + rollback

Roll `web` (Q3) to `nginx:1.28` with `maxSurge=1, maxUnavailable=0`. Verify image is updated. Then roll back to the previous revision.

## Q5 (6%) — ConfigMap + env + volume

In ns `q5`, create a ConfigMap `app-config` with `LOG_LEVEL=debug` and a file key `app.properties` containing `foo=bar`. Create a Pod `app` (`busybox:1.36`, `sleep 3600`) that:
- exposes `LOG_LEVEL` as an env var sourced from the ConfigMap
- mounts the ConfigMap as a volume at `/etc/app`

## Q6 (6%) — Probes

In ns `q6`, create a Deployment `web` (`nginx:1.27`, 2 replicas) with:
- a `readinessProbe` that httpGets `/` on port 80, period 5s
- a `livenessProbe` that httpGets `/` on port 80, period 10s, failure threshold 3

## Q7 (6%) — PVC + mount

In ns `q7`, create a PVC `data` requesting 500Mi RWO. Mount it at `/data` in a pod `writer` (`busybox:1.36`, `sleep 3600`). Verify the pod is `Running` and PVC is `Bound`.

## Q8 (7%) — NetworkPolicy

In ns `q8`, create a NetworkPolicy `allow-frontend`:
- selects pods labeled `role=backend`
- allows ingress from pods labeled `role=frontend` on TCP port 8080
- denies all other ingress to backend pods

## Q9 (6%) — Scheduling

Add a taint `env=prod:NoSchedule` to node `cka-worker2`. Create a Deployment `prod-app` (`nginx:1.27`, 2 replicas) in ns `q9` that **tolerates** this taint AND uses a nodeAffinity that requires `kubernetes.io/os=linux`.

## Q10 (7%) — RBAC

In ns `q10`, create a ServiceAccount `dev`, a Role allowing `get,list,watch` on `pods` and `deployments.apps`, and a RoleBinding tying them together.

Verify with:
```sh
k auth can-i list pods -n q10 --as=system:serviceaccount:q10:dev   # must be yes
k auth can-i delete pods -n q10 --as=system:serviceaccount:q10:dev # must be no
```

## Q11 (7%) — Helm install + upgrade

In ns `q11`, install the `bitnami/nginx` chart version `18.2.0` as a release named `web` with `replicaCount=3` and `service.type=ClusterIP`. Then upgrade to `replicaCount=5`. Show `helm history web -n q11` with at least 2 revisions.

## Q12 (6%) — Kustomize

Create a Kustomize `base/` (Deployment `web` from `nginx:1.27` + Service) and an `overlay/prod/` that:
- sets namespace `q12`
- bumps the image to `nginx:1.28`
- sets replicas to 5

Apply with `kubectl apply -k overlay/prod`. Show `kubectl -n q12 get deploy` reflecting the overlay values.

## Q13 (7%) — HPA

In ns `q13`, the Deployment `web` already exists with `requests.cpu=100m`. Create an HPA named `web` that scales between **2 and 8** replicas based on **70%** CPU utilization. Verify `kubectl get hpa web -n q13` shows it active (TARGETS not `<unknown>` after metrics-server warms up).

## Q14 (10%) — etcd backup

On the `cp` node (SSH provided), take an etcd snapshot to `/tmp/exam-backup.db` using the certs in `/etc/kubernetes/pki/etcd/`. Verify with `etcdctl snapshot status /tmp/exam-backup.db -w table`.

## Q15 (11%) — Troubleshoot

In ns `broken`, the Deployment `webapp` is failing to come up. Diagnose the root cause and fix it. Write the one-sentence root cause to `/tmp/q15-rca.txt`.

(Possible causes include: bad image tag, wrong ConfigMap reference, missing Secret, probe pointing at the wrong port, NetworkPolicy blocking a sidecar — diagnose from events and logs.)

---

## Scoring

- 66% to pass on the real CKA
- This mock targets the same threshold (15-task version: aim for 10+ fully correct, partial credit on the rest)
- Trainer reviews after time is up; we score together

## Tips you have ten seconds to read

- Skim **all** questions first. Mark ★/★★/★★★. Do ★ first.
- Set namespace + context **before** every question.
- Use `$do` to generate YAML. Don't type Pod YAML from scratch.
- `k explain --recursive <kind>` beats hunting docs pages.
- If stuck > 8 min: flag and move on. Come back.
- Verify before moving on — "must work" means `curl` it.
