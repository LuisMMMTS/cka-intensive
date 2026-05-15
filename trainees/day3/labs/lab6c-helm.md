# Lab 6c — Helm

**Time:** 30 min
**Goal:** install, override, upgrade, rollback a chart.

Verify Helm 3 is installed:
```sh
helm version    # v3.16+
```

---

## 6c.1 Add a repo

```sh
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
helm search repo bitnami/nginx
```

## 6c.2 Install with overrides

```sh
helm install web bitnami/nginx \
  --namespace web --create-namespace \
  --version 18.2.0 \
  --set service.type=ClusterIP \
  --set replicaCount=3
```

Verify:
```sh
helm list -n web
k -n web get all
helm get values web -n web
```

## 6c.3 Render only (no apply)

```sh
helm template web bitnami/nginx --set replicaCount=3 | less
```

This is what `helm install` would create. Skim it — see how `service.type` and `replicaCount` propagate.

## 6c.4 Upgrade

```sh
helm upgrade web bitnami/nginx -n web --reuse-values --set replicaCount=5
k -n web get deploy
helm history web -n web
```

`--reuse-values` keeps your previous overrides. Without it, you'd reset to defaults.

## 6c.5 Rollback

```sh
helm rollback web 1 -n web        # back to the first install
helm history web -n web           # see the rollback recorded as a new revision
k -n web get deploy               # replicaCount back to 3
```

## 6c.6 Use a values file (the production pattern)

Create `values-staging.yaml`:

```yaml
replicaCount: 2
service:
  type: ClusterIP
podAnnotations:
  env: staging
```

```sh
helm upgrade --install web bitnami/nginx \
  -n web -f values-staging.yaml \
  --version 18.2.0
```

`upgrade --install` is idempotent — works for both first install and subsequent upgrades. **Use this in CI.**

## 6c.7 Uninstall

```sh
helm uninstall web -n web
k delete ns web
```

## Deliverable

Show the trainer:
- `helm history web -n web` showing at least three revisions
- The rolled-back state (replicaCount=3 after rollback)
- `helm template` output piped through `less`
