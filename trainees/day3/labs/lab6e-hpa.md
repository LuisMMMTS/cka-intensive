# Lab 6e — HPA

**Time:** 30 min
**Goal:** install metrics-server, deploy with resource requests, autoscale on CPU.

Work in namespace `lab6e`:
```sh
k create ns lab6e && k config set-context --current --namespace=lab6e
```

---

## 6e.1 Install metrics-server

```sh
k apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

**On kind clusters**, edit the deployment and add `--kubelet-insecure-tls` to the metrics-server container args:

```sh
k -n kube-system edit deploy metrics-server
# add to .spec.template.spec.containers[0].args:
#   - --kubelet-insecure-tls
```

Wait ~30s, verify:
```sh
k -n kube-system get pods -l k8s-app=metrics-server
k top nodes
k top pods -A
```

If `top` returns errors for ~60s after install — be patient. metrics-server needs one scrape cycle.

**Hangs longer than ~2 min?** metrics-server is sick. Most common cause
on kind clusters: `--kubelet-insecure-tls` was never added. Check:

```sh
k -n kube-system describe deploy metrics-server | grep -A2 Args:
# Should include: --kubelet-insecure-tls
k -n kube-system logs -l k8s-app=metrics-server | tail
# Look for TLS errors connecting to kubelets (x509: ...)
```

If the flag is missing, re-run the patch from 6e.1.

## 6e.2 Deploy with requests

```sh
k create deploy web --image=nginx:1.27 --replicas=1 --port=80 \
  --dry-run=client -o yaml > /tmp/web.yaml
```

Edit `/tmp/web.yaml` to add resources:

```yaml
        resources:
          requests:
            cpu: 100m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 128Mi
```

```sh
k apply -f /tmp/web.yaml
k expose deploy web --port=80
```

## 6e.3 Create the HPA

```sh
k autoscale deploy web --min=2 --max=10 --cpu-percent=50
k get hpa web
# NAME   REFERENCE        TARGETS         MINPODS   MAXPODS   REPLICAS
# web    Deployment/web   <unknown>/50%   2         10        1
```

`<unknown>` for a few seconds is normal. Wait, and it becomes `0%/50%`.

Note: HPA already scaled up from 1 → 2 because of `min=2`.

## 6e.4 Generate load

In another terminal, run:

```sh
k run hey --rm -it --image=ghcr.io/rakyll/hey -- -z 5m -c 50 http://web
```

This sends concurrent requests for 5 minutes. CPU on `web` pods will spike.

In the first terminal:
```sh
k get hpa web -w
k top pods -l app=web
```

Within ~30–60s you should see `TARGETS` climb past 50% and `REPLICAS` grow toward the max.

## 6e.5 Watch it scale down

Kill the load (Ctrl-C the `hey` pod). HPA has a default **5-minute stabilization window** for scale-down (it doesn't bounce on noise).

```sh
k get hpa web -w
```

Eventually replicas drop back toward 2.

## 6e.6 Add a memory metric (HPA v2)

```sh
k get hpa web -o yaml > /tmp/hpa.yaml
```

Add to `spec.metrics`:

```yaml
  - type: Resource
    resource:
      name: memory
      target:
        type: AverageValue
        averageValue: 100Mi
```

Apply. Verify with `k describe hpa web`.

HPA scales to satisfy **whichever metric demands more replicas**.

## Cleanup

```sh
k delete ns lab6e
```

## Deliverable

Show the trainer:
- `k top pods -l app=web` showing real metrics
- HPA scaled up under load (`k get hpa web` showing replicas > min)
- HPA scaled back down after load stops
