# Lab 8 — etcd Backup & Restore

**Time:** 45 min
**Goal:** snapshot etcd, deliberately destroy state, restore. **This is on every CKA exam.**

By Lab 8 you have a single-node kubeadm cluster running directly on your
Debian VM (from Lab 7). Run these commands on the Debian VM as root (or
with `sudo`):

```sh
sudo -i
```

> If you didn't finish Lab 7 / want to start fresh, the trainer will
> snapshot-restore you to a known kubeadm cluster first.

## 8.1 Find the bits you need

The static-pod manifest tells you everything:

```sh
sudo cat /etc/kubernetes/manifests/etcd.yaml | grep -E 'cert|key|trusted-ca|listen-client'
```

You need:
- `--cacert=/etc/kubernetes/pki/etcd/ca.crt`
- `--cert=/etc/kubernetes/pki/etcd/server.crt`
- `--key=/etc/kubernetes/pki/etcd/server.key`
- `--endpoints=https://127.0.0.1:2379`

`etcdctl` was pre-installed on your Debian VM by the template. Verify:

```sh
which etcdctl && etcdctl version
```

## 8.2 Create some state to lose

```sh
kubectl create ns important
kubectl -n important create deploy victim --image=nginx:1.27
kubectl -n important get all
```

## 8.3 Snapshot

```sh
sudo ETCDCTL_API=3 etcdctl snapshot save /tmp/etcd-backup.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

sudo ETCDCTL_API=3 etcdctl snapshot status /tmp/etcd-backup.db -w table
```

## 8.4 Destroy something

```sh
kubectl delete ns important
kubectl get ns | grep important || echo "gone"
```

## 8.5 Restore

Stop the static-pod control plane:
```sh
sudo mv /etc/kubernetes/manifests /etc/kubernetes/manifests.bak
# wait until kube-apiserver and etcd containers are gone:
sudo crictl ps | grep -E 'etcd|apiserver' || echo "control plane down"
```

Restore to a new data dir, then point etcd at it:
```sh
sudo ETCDCTL_API=3 etcdctl snapshot restore /tmp/etcd-backup.db \
  --data-dir=/var/lib/etcd-restore

sudo mv /var/lib/etcd /var/lib/etcd.old
sudo mv /var/lib/etcd-restore /var/lib/etcd
sudo chown -R etcd:etcd /var/lib/etcd 2>/dev/null || true
```

Bring control plane back up:
```sh
sudo mv /etc/kubernetes/manifests.bak /etc/kubernetes/manifests
# wait ~30s
kubectl get ns | grep important       # should be back!
kubectl -n important get all          # victim deployment restored
```

Sanity-check etcd itself after the restore (the real exam often asks
this as proof):

```sh
sudo ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint health                    # → 127.0.0.1:2379 is healthy
sudo ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  member list -w table               # one member, the restored one
```

## Deliverable

`kubectl get ns important` after restore.

## Memorize this command

You will type this on exam day. Practice until you can write it without docs:

```sh
ETCDCTL_API=3 etcdctl snapshot save <path> \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key
```
