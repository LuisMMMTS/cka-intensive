# Lab 3b — Gateway API mini

**Time:** 25 min
**Goal:** wire a Gateway + HTTPRoute with traffic splitting.

### Pre-install (~2 min — trainer projects this once; everyone runs on their VM)

Gateway API CRDs and the Contour controller aren't on the cluster by
default. Run the install script:

```sh
~/cka-intensive/infra/scripts/install-gateway-api.sh
```

This installs Gateway API v1.2.0 standard CRDs, the Contour
Gateway-provisioner, and a `GatewayClass` named `contour`. Idempotent —
re-running is a no-op. Pass `--uninstall` to remove everything (the
cleanup before Day 4 mock exam does this via `kind-reset.sh`).

Verify:

```sh
k get crd | grep gateway.networking.k8s.io
# gatewayclasses.gateway.networking.k8s.io
# gateways.gateway.networking.k8s.io
# httproutes.gateway.networking.k8s.io
# ...
k -n projectcontour get pods                # Running
k get gatewayclass                          # contour
```

Work in namespace `lab3b`:
```sh
k create ns lab3b && k config set-context --current --namespace=lab3b
```

---

## 3b.1 Two backend Deployments

```sh
k create deploy v1 --image=hashicorp/http-echo --replicas=2 -- -text="v1"
k create deploy v2 --image=hashicorp/http-echo --replicas=2 -- -text="v2"
k expose deploy v1 --port=80 --target-port=5678
k expose deploy v2 --port=80 --target-port=5678
```

Confirm both work:
```sh
k run dbg --rm -it --image=curlimages/curl -- sh
> curl http://v1
> curl http://v2
```

## 3b.2 A Gateway

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: app-gw
  namespace: lab3b
spec:
  gatewayClassName: contour
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      allowedRoutes:
        namespaces: { from: Same }
```

Apply, then `k describe gateway app-gw` — wait for `Programmed: True`.

## 3b.3 An HTTPRoute with traffic split

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: app
  namespace: lab3b
spec:
  parentRefs:
    - { name: app-gw }
  hostnames: [app.local]
  rules:
    - matches:
        - path: { type: PathPrefix, value: / }
      backendRefs:
        - { name: v1, port: 80, weight: 80 }
        - { name: v2, port: 80, weight: 20 }
```

## 3b.4 Verify the split

Get the Envoy/Contour service's ClusterIP:

```sh
k -n projectcontour get svc envoy
```

From a debug pod:

```sh
k run dbg --rm -it --image=curlimages/curl -- sh
> for i in $(seq 1 20); do curl -sH 'Host: app.local' http://<envoy-ip>/; done
```

Roughly 16 `v1` and 4 `v2`. (Not exactly 80/20 — small samples are noisy.)

## 3b.5 Header-based routing

Add a second rule to the HTTPRoute that, when the request has header `x-version: v2`, routes 100% to `v2`:

```yaml
    - matches:
        - path: { type: PathPrefix, value: / }
          headers:
            - { name: x-version, value: v2 }
      backendRefs:
        - { name: v2, port: 80 }
```

(Put this rule **before** the splitting rule — Gateway API evaluates rules top-down.)

Verify:
```sh
curl -sH 'Host: app.local' -H 'x-version: v2' http://<envoy-ip>/   # always v2
curl -sH 'Host: app.local' http://<envoy-ip>/                       # 80/20 split
```

## Cleanup

```sh
k delete ns lab3b
```

## Deliverable

Show the trainer:
- The Gateway is `Programmed: True`
- 20 curls split roughly 80/20 between v1 and v2
- The header rule pins to v2
