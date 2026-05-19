# Lab 2 — Workload Types

**Time:** 60 min
**Goal:** create and reason about each controller type.

Work in namespace `lab2`: `k create ns lab2 && k config set-context --current --namespace=lab2`

## 2.1 Deployment with rolling update

```sh
k create deploy web --image=nginx:1.27 --replicas=3
k get deploy,rs,pods                                # see all three layers
k expose deploy web --port=80                       # for the wget loop below
```

In a **second terminal**, start a continuous probe so you can watch zero downtime:

```sh
k run probe --rm -it --image=busybox:1.36 --restart=Never -- \
  sh -c 'while true; do wget -qO- web && echo; sleep 0.5; done'
```

Back in the first terminal, roll out a new image:

```sh
k set image deploy/web nginx=nginx:1.28
k rollout status deploy/web                         # blocks until done
k rollout history deploy/web                        # see revisions
```

The probe should print the nginx welcome page continuously — zero
dropped requests. If you see a connection reset, you've found the
default RollingUpdate parameters' edge case.

Rollback if you want to see it:
```sh
k rollout undo deploy/web
```

## 2.2 DaemonSet

There is no `kubectl create daemonset` generator. Start from a Deployment
YAML, change `kind: DaemonSet`, drop `replicas` and `strategy`:

```sh
k create deploy node-watch --image=busybox:1.36 $do -- sleep 86400 > /tmp/ds.yaml
```

Edit `/tmp/ds.yaml`:
- `kind: Deployment` → `kind: DaemonSet`
- Delete `spec.replicas`
- Delete `spec.strategy`

Then:
```sh
k apply -f /tmp/ds.yaml
k get ds,pods -o wide                               # confirm one pod per node
```

Or you can paste this YAML directly:

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata: { name: node-watch }
spec:
  selector: { matchLabels: { app: node-watch } }
  template:
    metadata: { labels: { app: node-watch } }
    spec:
      containers:
        - name: nw
          image: busybox:1.36
          command: [sh, -c, "sleep 86400"]
```

## 2.3 StatefulSet

Create a StatefulSet `db` with 3 replicas using `nginx:1.27` (use the alpine image as a stand-in for a stateful workload). Observe ordered pod naming: `db-0`, `db-1`, `db-2`. Delete `db-1` and watch it get recreated with the same name.

Note: needs a headless Service. Create both:

```yaml
apiVersion: v1
kind: Service
metadata: { name: db }
spec:
  clusterIP: None
  selector: { app: db }
  ports: [{ port: 80 }]
---
apiVersion: apps/v1
kind: StatefulSet
metadata: { name: db }
spec:
  serviceName: db
  replicas: 3
  selector: { matchLabels: { app: db } }
  template:
    metadata: { labels: { app: db } }
    spec:
      containers:
        - name: nginx
          image: nginx:1.27
          ports: [{ containerPort: 80 }]
```

## 2.4 Job and CronJob

```sh
# Job: run-to-completion
k create job pi --image=perl:5.34 -- perl -Mbignum=bpi -wle 'print bpi(200)'
k get jobs,pods
k logs job/pi                              # see the digits of pi
k wait --for=condition=Complete job/pi --timeout=120s

# CronJob: scheduled Job factory
k create cronjob hello --image=busybox:1.36 \
  --schedule="*/1 * * * *" -- /bin/sh -c 'echo hello at $(date)'
k get cronjob,jobs,pods
# wait 60s, then check that a Job got spawned:
k get jobs -w                              # Ctrl-C after you see a job appear
```

## Cleanup

```sh
k delete ns lab2
```

## Deliverable

Show the trainer:
- `k get all` in `lab2` showing all controller types
- `k get pods -o wide` proving the DaemonSet runs on every worker
