# CKA Survival Cheatsheet — v1.36

## Shell setup (do this every fresh terminal in the exam)

```sh
alias k=kubectl
source <(kubectl completion bash)
complete -F __start_kubectl k
export do='--dry-run=client -o yaml'
export now='--grace-period=0 --force'
```

## Context / namespace (FIRST thing on every question)

```sh
k config get-contexts
k config use-context <ctx>
k config set-context --current --namespace=<ns>
k config view --minify             # what am I pointed at right now?
```

## Imperative one-liners

```sh
k run nginx --image=nginx                                # pod
k run nginx --image=nginx $do > pod.yaml                 # pod YAML
k create deploy web --image=nginx --replicas=3           # deployment
k expose deploy web --port=80 --target-port=80           # service (ClusterIP)
k expose deploy web --port=80 --type=NodePort            # nodeport
k create cm app --from-literal=KEY=val                   # configmap
k create cm app --from-file=app.properties               # configmap from file
k create secret generic db --from-literal=password=p     # secret
k create secret tls web-tls --cert=tls.crt --key=tls.key # tls secret
k create sa dev                                          # serviceaccount
k create role r --verb=get,list --resource=pods          # role
k create rolebinding rb --role=r --serviceaccount=ns:dev # rolebinding
k create clusterrole cr --verb=get --resource=nodes      # clusterrole
k create clusterrolebinding crb --clusterrole=cr --user=alice # crb
k create job hello --image=busybox -- echo hi            # job
k create cronjob c --image=busybox --schedule="*/1 * * * *" -- echo hi  # cronjob
k create quota nq --hard=cpu=2,memory=1Gi,pods=5         # resourcequota
k autoscale deploy web --min=2 --max=10 --cpu-percent=60 # hpa
k create token <sa> --duration=1h                        # SA token
```

## Rollouts (Deployments) — exam-critical

```sh
k set image deploy/web nginx=nginx:1.28           # roll forward
k rollout status deploy/web                       # block until done (exit 0 = success)
k rollout history deploy/web                      # list revisions
k rollout history deploy/web --revision=2         # what was in rev 2?
k rollout undo deploy/web                         # back to previous rev
k rollout undo deploy/web --to-revision=1         # back to a specific rev
k rollout restart deploy/web                      # trigger a roll without spec change
k rollout pause deploy/web                        # pause mid-roll (canary pattern)
k rollout resume deploy/web
```

## Scaling

```sh
k scale deploy web --replicas=5
k scale --replicas=0 deploy/web                   # quick "off" switch
k scale --current-replicas=3 --replicas=5 deploy/web  # CAS-style (fails if not 3)
```

## StatefulSet (the headless-service pattern)

```yaml
# 1. Headless Service — clusterIP: None — gives stable per-pod DNS
apiVersion: v1
kind: Service
metadata: { name: db }
spec:
  clusterIP: None
  selector: { app: db }
  ports: [{ port: 80 }]
---
# 2. StatefulSet — pods get stable names: db-0, db-1, db-2
apiVersion: apps/v1
kind: StatefulSet
metadata: { name: db }
spec:
  serviceName: db              # must match the headless service name
  replicas: 3
  selector: { matchLabels: { app: db } }
  template:
    metadata: { labels: { app: db } }
    spec:
      containers:
        - { name: nginx, image: nginx:1.27, ports: [{ containerPort: 80 }] }
```

Stable DNS from inside the cluster: `db-0.db.<ns>.svc.cluster.local`.
Delete `db-1` → it comes back as `db-1` (not a random name).

## DaemonSet (no imperative generator — create from Deployment)

```sh
k create deploy node-watch --image=busybox:1.36 $do -- sleep 86400 > /tmp/ds.yaml
# Edit: kind: Deployment → kind: DaemonSet; remove spec.replicas + spec.strategy
k apply -f /tmp/ds.yaml
k get ds,pods -o wide                             # one pod per node
```

## Inspection

```sh
k get all -A
k get events --sort-by=.lastTimestamp -A
k get pods -A -o wide --field-selector=status.phase=Pending
k describe pod <p>                       # always check the Events at the bottom
k logs <p> -c <container> --previous
k exec -it <p> -- sh
k get pod <p> -o yaml
k get pod <p> -o jsonpath='{.status.podIP}'
k explain deployment.spec.strategy --recursive
k auth can-i <verb> <resource> -n <ns> --as=system:serviceaccount:ns:sa
```

## Node ops (drain/cordon/uncordon)

```sh
k cordon <node>
k drain <node> --ignore-daemonsets --delete-emptydir-data
k uncordon <node>
k taint node <n> key=val:NoSchedule
k taint node <n> key:NoSchedule-           # remove
k label node <n> key=val
k label node <n> key-                      # remove
```

## metrics-server (for `kubectl top` and HPA)

Already installed on our kind cluster. If you need to re-install:

```sh
k apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
# On clusters with self-signed kubelet certs (kind, kubeadm): add `--kubelet-insecure-tls`
k -n kube-system patch deploy metrics-server --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
k top nodes
k top pods -A
```

## etcd backup (memorize — on every exam)

```sh
ETCDCTL_API=3 etcdctl snapshot save /tmp/snap.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

ETCDCTL_API=3 etcdctl snapshot status /tmp/snap.db -w table

# restore:
sudo mv /etc/kubernetes/manifests /etc/kubernetes/manifests.bak
ETCDCTL_API=3 etcdctl snapshot restore /tmp/snap.db --data-dir=/var/lib/etcd-restore
sudo mv /var/lib/etcd /var/lib/etcd.old && sudo mv /var/lib/etcd-restore /var/lib/etcd
sudo mv /etc/kubernetes/manifests.bak /etc/kubernetes/manifests
```

## kubeadm upgrade flow (memorize — to v1.36.x)

```sh
# control plane (first cp)
k drain <cp> --ignore-daemonsets
sudo apt-get update && sudo apt-get install -y kubeadm=1.36.x-*
sudo kubeadm upgrade plan
sudo kubeadm upgrade apply v1.36.x
sudo apt-get install -y kubelet=1.36.x-* kubectl=1.36.x-*
sudo systemctl daemon-reload && sudo systemctl restart kubelet
k uncordon <cp>

# additional CPs: same but `kubeadm upgrade node` instead of `apply`

# workers (one at a time)
k drain <w> --ignore-daemonsets
# on worker:
sudo apt-get install -y kubeadm=1.36.x-*
sudo kubeadm upgrade node
sudo apt-get install -y kubelet=1.36.x-* kubectl=1.36.x-*
sudo systemctl daemon-reload && sudo systemctl restart kubelet
k uncordon <w>
```

## TLS cert management (kubeadm)

```sh
sudo kubeadm certs check-expiration
sudo kubeadm certs renew all          # renew everything
sudo kubeadm certs renew apiserver    # renew one
sudo systemctl restart kubelet
```

## Helm

```sh
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
helm search repo nginx

helm install web bitnami/nginx -n web --create-namespace --version 18.2.0 \
  --set replicaCount=3 --set service.type=ClusterIP
helm upgrade --install web bitnami/nginx -n web -f values.yaml
helm rollback web 1 -n web
helm history web -n web
helm uninstall web -n web

helm template web ./mychart -f values-prod.yaml | less
helm get values web -n web
helm get manifest web -n web
```

## Kustomize (built into kubectl)

```sh
k kustomize overlays/prod        # render only
k apply -k overlays/prod         # render + apply
k delete -k overlays/prod
```

Minimal `kustomization.yaml`:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: prod
resources: [../../base]
images: [{ name: nginx, newTag: "1.28" }]
patches:
  - target: { kind: Deployment, name: web }
    patch: |
      - op: replace
        path: /spec/replicas
        value: 5
```

## ConfigMap / Secret — three consumption patterns (memorize)

Same shape for both. Swap `configMapKeyRef`→`secretKeyRef`,
`configMapRef`→`secretRef`, `configMap:`→`secret:` / `secretName:`.

```yaml
spec:
  containers:
    - name: app
      image: busybox:1.36
      env:                                       # 1) ONE key as env
        - name: LOG_LEVEL
          valueFrom: { configMapKeyRef: { name: app-config, key: LOG_LEVEL } }
        - name: DB_PASS
          valueFrom: { secretKeyRef:    { name: db,         key: password  } }
      envFrom:                                   # 2) ALL keys as env
        - configMapRef: { name: app-config }
        - secretRef:    { name: db }
      volumeMounts:                              # 3) MOUNTED as files
        - { name: cfg,     mountPath: /etc/app, readOnly: true }
        - { name: dbcreds, mountPath: /etc/db,  readOnly: true }
  volumes:
    - name: cfg
      configMap: { name: app-config }
    - name: dbcreds
      secret:
        secretName: db
        defaultMode: 0400                        # Secret-only: tighten perms
```

**Refresh on update**: env vars NEVER refresh (restart pod). Mounted
volumes refresh ~60s, unless `subPath:` is set (then never). Use the
volume pattern for TLS rotation.

## NetworkPolicy default-deny (memorize)

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: default-deny }
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
```

## Probe basics

Probes live on the **container**, not the pod. For a Deployment:
`spec.template.spec.containers[N].{liveness,readiness,startup}Probe`.

```yaml
spec:
  containers:
    - name: app
      image: nginx:1.27
      livenessProbe:  { httpGet: { path: /healthz, port: 8080 }, periodSeconds: 10, failureThreshold: 3 }
      readinessProbe: { tcpSocket: { port: 8080 }, periodSeconds: 5 }
      startupProbe:   { httpGet: { path: /, port: 8080 }, failureThreshold: 30, periodSeconds: 2 }
```

Handler types (one per probe): `httpGet`, `tcpSocket`, `exec: { command: [...] }`.
Liveness failure → restart. Readiness failure → drop from Service endpoints.
Startup gates the other two while it runs.

## Docs bookmarks (allowed in the exam)

- https://kubernetes.io/docs/reference/kubectl/quick-reference/
- https://kubernetes.io/docs/concepts/workloads/pods/
- https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/
- https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/
- https://kubernetes.io/docs/concepts/services-networking/network-policies/
- https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/
- https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/
- https://helm.sh/docs/intro/quickstart/
- https://gateway-api.sigs.k8s.io/guides/

## Time strategy

- 2 hours, ~15–20 questions = ~6–7 min/question average
- **Skim ALL questions first**, mark "easy/medium/hard" — do easy first
- Each question shows weight (%); a 10% q is worth more than a 4% q
- Use `kubectl --context=<ctx>` if switching takes too long
- If stuck > 8 min on one question, **FLAG and move on**
- Always verify the question's success criteria before moving on — "service must be reachable" means `curl` it
