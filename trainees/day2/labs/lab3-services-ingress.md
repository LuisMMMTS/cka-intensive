# Lab 3 — Services & Ingress

**Time:** 60 min
**Goal:** expose workloads with each Service type, then add Ingress.

`k create ns lab3 && k config set-context --current --namespace=lab3`

## 3.1 ClusterIP

```sh
k create deploy web --image=nginx:1.27 --replicas=2
k expose deploy web --port=80
k get endpoints web
k run tmp --rm -it --image=busybox:1.36 --restart=Never -- wget -qO- web
```

## 3.2 NodePort

```sh
k expose deploy web --name=web-np --type=NodePort --port=80
k get svc web-np    # note the port (3xxxx)
# Reach a node from your host via the kind container's IP:
WORKER_IP=$(docker inspect cka-worker --format '{{.NetworkSettings.Networks.kind.IPAddress}}')
curl -s "$WORKER_IP:<nodeport>"
```

## 3.3 Headless service

Create a service `web-headless` with `clusterIP: None`. Resolve it with `nslookup web-headless` from inside a pod and notice you get pod IPs back.

## 3.4 Ingress

Install ingress-nginx (kind has docs for this):

```sh
k apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
k wait -n ingress-nginx --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller --timeout=180s
```

> Note: our kind cluster maps host ports 80/443 to the control-plane node,
> so an Ingress on `ingress-ready=true` nodes will be reachable at
> `http://localhost`. If port 80 is already taken on your VM, use
> `kubectl -n ingress-nginx port-forward svc/ingress-nginx-controller 8080:80`
> and curl `http://localhost:8080`.

Create an Ingress that routes `web.cka.local` → service `web:80`:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web
spec:
  ingressClassName: nginx
  rules:
    - host: web.cka.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: web
                port: { number: 80 }
```

Test:
```sh
curl -H 'Host: web.cka.local' http://localhost
```

(If port 80 isn't mapped to your VM, use port-forward:
```sh
k -n ingress-nginx port-forward svc/ingress-nginx-controller 8080:80 &
curl -H 'Host: web.cka.local' http://localhost:8080
kill %1
```)

## Deliverable

`curl -H 'Host: web.cka.local' http://localhost` returns the nginx welcome page.
