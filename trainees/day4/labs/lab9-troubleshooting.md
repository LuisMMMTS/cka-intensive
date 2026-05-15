# Lab 9 — Troubleshooting

**Time:** 60 min
**Goal:** systematic debugging of broken clusters and broken apps.
Troubleshooting is **30% of the exam**.

Before the lab, the trainer will run `./kind-reset.sh` (or have you do it)
to start from a clean 3-node kind cluster, then run a scenario script
that breaks one specific thing on your cluster. You won't know which one — that's the point.

```sh
# Trainer assigns each trainee one of A/B/C/D and runs the matching script.
# Don't peek at the others — your neighbor might have a different one.
```

## The troubleshooting algorithm (memorize)

1. **`kubectl get`** the resource — what's its status?
2. **`kubectl describe`** — what's in the events?
3. **`kubectl logs`** (and `--previous` for crashed containers)
4. **Node-level**: `docker exec -it <node> bash`, then `journalctl -u kubelet`, `crictl ps -a`, `crictl logs`
5. **Component-level**: `/etc/kubernetes/manifests/`, static pod definitions
6. **Network**: `nslookup` from inside a pod, check NetworkPolicies, check Service endpoints

## Scenario menu (one will apply to you)

### A. Broken kubelet on a worker

Symptom: `kubectl get nodes` shows one of the workers as `NotReady`.

Investigate:

```sh
kubectl describe node cka-worker                       # or whichever
# (look at "Conditions" — what does the kubelet say?)

docker exec -it cka-worker bash
sudo systemctl status kubelet
sudo journalctl -u kubelet -n 100 --no-pager
```

The kubelet's `Loaded:` and `Active:` lines tell you most of the story.

### B. Broken control-plane static pod

Symptom: `kubectl get pods` returns "connection refused" or hangs.

Investigate:

```sh
docker exec -it cka-control-plane bash
sudo crictl ps -a | grep -E 'apiserver|scheduler|controller-manager|etcd'
# find the failing one, then:
sudo crictl logs <container-id>

# Static pod manifests are here:
sudo ls /etc/kubernetes/manifests/
sudo cat /etc/kubernetes/manifests/kube-apiserver.yaml
```

Hint: most control-plane breakage comes from a typo in one of those manifests
(bad flag, bad path, wrong port). The kubelet auto-recreates static pods when
the file changes, so editing the manifest is the fix.

### C. Broken DNS

Symptom: pods can reach each other by IP but not by service name.

Investigate:

```sh
kubectl -n kube-system get pods -l k8s-app=kube-dns
kubectl -n kube-system logs -l k8s-app=kube-dns
kubectl -n kube-system describe deploy coredns

kubectl run dnstest --rm -it --image=busybox:1.36 --restart=Never -- \
  nslookup kubernetes.default
```

What's the actual state of the CoreDNS deployment? Replicas? Pods Running?
Service endpoints populated?

### D. Broken app

Symptom: a Deployment in namespace `broken` won't become Ready.

Investigate:

```sh
kubectl -n broken get pods
kubectl -n broken describe pod <pod>
kubectl -n broken logs <pod>
kubectl -n broken get events --sort-by=.lastTimestamp
```

Common culprits: bad image tag, missing ConfigMap/Secret, bad env var, wrong
port, resource requests too high, probe pointing at the wrong path.

## Hints (don't read until stuck for 10 min)

<details>
<summary>Scenario A hint</summary>
The kubelet has been stopped AND `mask`-ed. `systemctl status` will show
`Loaded: masked`. You need `unmask` and `start`.
</details>

<details>
<summary>Scenario B hint</summary>
Look at the kube-apiserver manifest's `--etcd-servers` flag. The port may be
wrong (9999 instead of 2379). Save the fix; kubelet reloads within 10s.
</details>

<details>
<summary>Scenario C hint</summary>
CoreDNS deployment has been scaled to 0 replicas. `kubectl scale` it back to 2.
</details>

<details>
<summary>Scenario D hint</summary>
`kubectl -n broken describe pod ...` will show "Failed to pull image" with the
exact bad image. `kubectl -n broken set image deploy/webapp ...=nginx:1.27`
fixes it.
</details>

## Deliverable

Show the trainer:

1. **The diagnosis** (one sentence: what was wrong)
2. **The fix** (the command(s) you ran)
3. **Proof it's fixed** — the node Ready / the apiserver responding / DNS
   resolving / the Deployment Ready

## After the lab

```sh
cd ~/cka-intensive/infra/scripts
./kind-reset.sh
```

~90s. Clean cluster for the mock exam.
