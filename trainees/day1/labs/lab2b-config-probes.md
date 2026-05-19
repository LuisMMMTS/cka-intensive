# Lab 2b — ConfigMaps, Secrets, Probes

**Time:** 45 min
**Goal:** wire config and health checks like the exam will ask you to.

Work in namespace `lab2b`:
```sh
k create ns lab2b && k config set-context --current --namespace=lab2b
```

---

## 2b.1 ConfigMap as env vars (single key)

```sh
k create cm app-config \
  --from-literal=LOG_LEVEL=debug \
  --from-literal=TIMEOUT=30s

k get cm app-config -o yaml
```

Pod `env1` with the single key wired as an env var:

```yaml
apiVersion: v1
kind: Pod
metadata: { name: env1 }
spec:
  containers:
    - name: c
      image: busybox:1.36
      command: [sh, -c, sleep 3600]
      env:
        - name: LOG_LEVEL
          valueFrom:
            configMapKeyRef: { name: app-config, key: LOG_LEVEL }
```

```sh
k apply -f env1.yaml
k exec env1 -- env | grep LOG_LEVEL          # LOG_LEVEL=debug
```

## 2b.2 ConfigMap as env vars (all keys)

Pod `env2`, same image and command, but use `envFrom` to inject **all** keys
of `app-config` at once:

```yaml
apiVersion: v1
kind: Pod
metadata: { name: env2 }
spec:
  containers:
    - name: c
      image: busybox:1.36
      command: [sh, -c, sleep 3600]
      envFrom:
        - configMapRef: { name: app-config }
```

```sh
k apply -f env2.yaml
k exec env2 -- env | grep -E '^(LOG_LEVEL|TIMEOUT)='   # both appear
```

## 2b.3 ConfigMap as a volume

Create a second ConfigMap `app-files`:

```sh
k create cm app-files \
  --from-literal=app.properties=$'foo=bar\nbaz=qux' \
  --from-literal=banner.txt='hello from k8s'
```

Pod `vol1`, mount `app-files` at `/etc/app`. Then:
```sh
k exec vol1 -- ls /etc/app
k exec vol1 -- cat /etc/app/app.properties
```

**Bonus:** edit the ConfigMap (`k edit cm app-files`), change `banner.txt`, wait ~60s, `cat` the file again from inside the pod. Did it update?

## 2b.4 Secret as env

```sh
k create secret generic db \
  --from-literal=username=admin \
  --from-literal=password=s3cret

k get secret db -o yaml          # values are base64'd (not encrypted!)
```

Pod `sec1` exposes them as `DB_USER` and `DB_PASS`:

```yaml
apiVersion: v1
kind: Pod
metadata: { name: sec1 }
spec:
  containers:
    - name: c
      image: busybox:1.36
      command: [sh, -c, sleep 3600]
      env:
        - name: DB_USER
          valueFrom: { secretKeyRef: { name: db, key: username } }
        - name: DB_PASS
          valueFrom: { secretKeyRef: { name: db, key: password } }
```

```sh
k apply -f sec1.yaml
k exec sec1 -- env | grep ^DB_   # DB_USER=admin, DB_PASS=s3cret
```

## 2b.5 Probes

Create a Deployment `web` (`nginx:1.27`, 3 replicas, port 80) with all three probes:

- **startup**: `httpGet /` on port 80; `failureThreshold: 30`, `periodSeconds: 2` (gives nginx 60s to boot)
- **readiness**: `httpGet /` on port 80; `periodSeconds: 5`
- **liveness**: `httpGet /` on port 80; `periodSeconds: 10`, `failureThreshold: 3`

Expose with a ClusterIP Service. From a debug pod, hit the service repeatedly.

## 2b.6 Break the readiness probe

**Setup:** patching the existing 3-replica `web` deployment won't drain its
endpoints — default RollingUpdate has `maxUnavailable=25%` which rounds
down to 0 at 3 replicas, so the old healthy pods stay alive forever while
the new broken pods fail to roll out. To see the actual readiness drain,
create a fresh deployment with the broken probe from the start.

Apply:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata: { name: broken-web }
spec:
  replicas: 3
  selector: { matchLabels: { app: broken-web } }
  template:
    metadata: { labels: { app: broken-web } }
    spec:
      containers:
        - name: nginx
          image: nginx:1.27
          ports: [{ containerPort: 80 }]
          readinessProbe:
            httpGet: { path: /this-does-not-exist, port: 80 }
            periodSeconds: 3
            failureThreshold: 2
```

```sh
k expose deploy broken-web --port=80
k get pods -l app=broken-web -w     # pods are Running but never Ready
k get endpoints broken-web          # no addresses — readiness keeps pods out
```

**Lesson:** a Service only routes to pods that are `Ready`. If readiness
fails, the pod stays in the cluster but the endpoint controller removes
it from the service's address list. Traffic is shed gracefully without
killing the pod.

## 2b.7 Break the liveness probe

Same trick on liveness. Watch the restart counter climb. This is what `CrashLoopBackOff` looks like before it lands in that state.

Roll back.

## Cleanup

```sh
k delete ns lab2b
```

## Deliverable

Show the trainer:
- `k get pods` showing the various env/volume/sec test pods
- A `describe` of `web` showing all three probes wired up
- The endpoints behavior when readiness fails (empty / repopulated)
