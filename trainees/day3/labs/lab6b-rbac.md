# Lab 6b — RBAC

**Time:** 45 min
**Goal:** create namespaced + cluster-wide permissions, verify with `auth can-i`, build a kubeconfig for an SA.

Work in namespace `team-a`:
```sh
k create ns team-a && k config set-context --current --namespace=team-a
```

---

## 6b.1 Namespaced read-only

Create:
- `ServiceAccount` `dev` in `team-a`
- `Role` `pod-reader` in `team-a` granting `get,list,watch` on `pods` and `pods/log`
- `RoleBinding` binding `pod-reader` to SA `team-a:dev`

Use `--dry-run=client -o yaml` to generate, then apply.

Verify:
```sh
k auth can-i list pods -n team-a --as=system:serviceaccount:team-a:dev   # yes
k auth can-i delete pods -n team-a --as=system:serviceaccount:team-a:dev # no
k auth can-i list pods -n default --as=system:serviceaccount:team-a:dev  # no (different ns)
```

## 6b.2 Extend to deployments

Edit the Role to also allow `get,list,watch` on `deployments.apps`.

```sh
k auth can-i list deploy -n team-a --as=system:serviceaccount:team-a:dev   # yes
```

## 6b.3 Cluster-wide read on nodes

Cluster-scoped resources require a `ClusterRole`. Create:
- `ClusterRole` `node-viewer` granting `get,list,watch` on `nodes`
- `ClusterRoleBinding` binding it to SA `team-a:dev`

```sh
k auth can-i list nodes --as=system:serviceaccount:team-a:dev    # yes
```

## 6b.4 Reuse a ClusterRole in one namespace only

The built-in `edit` ClusterRole allows RW on most namespaced resources.

Create a RoleBinding in `team-a` named `dev-edit` binding the `edit` ClusterRole to SA `team-a:dev`.

```sh
k auth can-i create deploy -n team-a --as=system:serviceaccount:team-a:dev   # yes
k auth can-i create deploy -n default --as=system:serviceaccount:team-a:dev  # no
```

The same ClusterRole gives namespaced powers via a RoleBinding.

## 6b.5 Build a kubeconfig for the SA

```sh
# generate a token for the SA (1h validity)
TOKEN=$(k create token dev -n team-a --duration=1h)

# get cluster info
APISERVER=$(k config view --minify -o jsonpath='{.clusters[0].cluster.server}')
CA=$(k config view --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')

# build a kubeconfig
cat > /tmp/dev.kubeconfig <<EOF
apiVersion: v1
kind: Config
clusters:
  - name: cka
    cluster:
      server: $APISERVER
      certificate-authority-data: $CA
users:
  - name: dev
    user:
      token: $TOKEN
contexts:
  - name: dev@cka
    context: { cluster: cka, user: dev, namespace: team-a }
current-context: dev@cka
EOF

# test the kubeconfig
KUBECONFIG=/tmp/dev.kubeconfig k get pods             # works (Role pod-reader)
KUBECONFIG=/tmp/dev.kubeconfig k get nodes            # works (ClusterRole node-viewer)
KUBECONFIG=/tmp/dev.kubeconfig k delete pod xyz       # forbidden
```

## Cleanup

```sh
k delete clusterrolebinding dev-binds-cluster      # whichever names you used
k delete clusterrole node-viewer
k delete ns team-a
rm /tmp/dev.kubeconfig
```

## Deliverable

Show the trainer:
- A passing `auth can-i list pods` and failing `auth can-i delete pods`
- A working `KUBECONFIG=... k get pods` as the SA
- The same failing for an action not in the bindings
