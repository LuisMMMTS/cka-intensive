# Lab 2 — Workload Types

**Time:** 60 min
**Goal:** create and reason about each controller type.

Work in namespace `lab2`: `k create ns lab2 && k config set-context --current --namespace=lab2`

## 2.1 Deployment with rolling update

Create `web` (3 replicas, `nginx:1.27`). Roll it to `nginx:1.28` and confirm zero downtime by running `wget` in a loop from another terminal.

## 2.2 DaemonSet

Create a DaemonSet `node-watch` running `busybox:1.36` with command `sleep 86400` on every node. Confirm one pod per node.

Hint: there is no `kubectl create daemonset` generator. Start from a Deployment YAML, change `kind: DaemonSet`, drop `replicas` and `strategy`.

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

Create a Job `pi` running `perl:5.34` with command `perl -Mbignum=bpi -wle "print bpi(200)"`. Confirm it completes.

Create a CronJob `hello` that runs every minute and echoes "hello at $(date)".

```sh
k create cronjob hello --image=busybox:1.36 --schedule="*/1 * * * *" -- /bin/sh -c 'echo hello at $(date)'
k get cronjob,jobs,pods
```

## Cleanup

```sh
k delete ns lab2
```

## Deliverable

Show the trainer:
- `k get all` in `lab2` showing all controller types
- `k get pods -o wide` proving the DaemonSet runs on every worker
