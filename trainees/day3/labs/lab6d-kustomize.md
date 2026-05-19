# Lab 6d — Kustomize

**Time:** 30 min
**Goal:** build a base + two overlays, apply each.

No external tool needed — `kubectl apply -k` is built in.

---

## 6d.1 Lay out the directories

```sh
mkdir -p ~/lab6d/base ~/lab6d/overlays/dev ~/lab6d/overlays/prod
cd ~/lab6d
```

## 6d.2 Base

`base/deployment.yaml`:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata: { name: web }
spec:
  replicas: 1
  selector: { matchLabels: { app: web } }
  template:
    metadata: { labels: { app: web } }
    spec:
      containers:
        - name: web
          image: nginx:1.27
          ports: [{ containerPort: 80 }]
          env:
            - { name: LOG_LEVEL, value: info }
```

`base/service.yaml`:
```yaml
apiVersion: v1
kind: Service
metadata: { name: web }
spec:
  selector: { app: web }
  ports: [{ port: 80, targetPort: 80 }]
```

`base/kustomization.yaml`:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - deployment.yaml
  - service.yaml
commonLabels:
  app: web
```

## 6d.3 Dev overlay

`overlays/dev/kustomization.yaml`:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: dev
resources:
  - ../../base
images:
  - { name: nginx, newTag: "1.27-alpine" }
patches:
  - target: { kind: Deployment, name: web }
    patch: |
      - op: replace
        path: /spec/replicas
        value: 1
```

## 6d.4 Prod overlay

`overlays/prod/kustomization.yaml`:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: prod
resources:
  - ../../base
images:
  - { name: nginx, newTag: "1.28" }
patches:
  - target: { kind: Deployment, name: web }
    patch: |
      - op: replace
        path: /spec/replicas
        value: 5
      - op: replace
        path: /spec/template/spec/containers/0/env/0/value
        value: warn
```

## 6d.5 Render and apply

```sh
k create ns dev && k create ns prod

k kustomize overlays/dev          # inspect rendered YAML
k apply -k overlays/dev

k kustomize overlays/prod
k apply -k overlays/prod

k -n dev get deploy web -o jsonpath='{.spec.replicas}{"\n"}'        # 1
k -n prod get deploy web -o jsonpath='{.spec.replicas}{"\n"}'       # 5
k -n prod get deploy web -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'  # nginx:1.28
k -n prod get deploy web -o jsonpath='{.spec.template.spec.containers[0].env}'          # LOG_LEVEL=warn
```

## 6d.6 configMapGenerator

Add to `overlays/prod/kustomization.yaml`:

```yaml
configMapGenerator:
  - name: env
    literals:
      - REGION=us-east-1
      - TIER=production
```

Re-apply. Kustomize generates a ConfigMap with a content-hash suffix (immutable releases).

```sh
k -n prod get cm
# env-7bgh8m4f7c    ← hash-suffixed name
```

## 6d.7 secretGenerator

Same idea as `configMapGenerator` but produces a Secret. Add to
`overlays/prod/kustomization.yaml`:

```yaml
secretGenerator:
  - name: db
    literals:
      - username=admin
      - password=s3cret
    type: Opaque                              # default; could also be kubernetes.io/tls
```

Re-apply, then verify a hash-suffixed Secret exists alongside the
hash-suffixed ConfigMap:

```sh
k apply -k overlays/prod
k -n prod get secret
# db-7m4f7gk2t9    Opaque    2      5s
```

The Secret's name is hash-suffixed for the same reason ConfigMaps are:
when the data changes, the generated name changes, which triggers a
Deployment rollout that references it (no manual rollout needed —
**immutable releases for secrets too**).

You can also use `files:` to pull Secret data from a file:

```yaml
secretGenerator:
  - name: web-tls
    files:
      - tls.crt
      - tls.key
    type: kubernetes.io/tls
```

## Cleanup

```sh
k delete ns dev prod
rm -rf ~/lab6d
```

## Deliverable

Show the trainer:
- `k kustomize overlays/prod` output
- Two namespaces with different replica counts and images
- The hash-suffixed ConfigMap
