# Lab 8b — CRDs and operators

**Time:** 30 min
**Goal:** install an operator, observe its CRDs and reconciliation, then break it.

---

## 8b.1 Install cert-manager

```sh
k apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml
```

Wait for the operator pods:
```sh
k -n cert-manager get pods -w
# cert-manager-*
# cert-manager-cainjector-*
# cert-manager-webhook-*
```

All three Ready before continuing.

## 8b.2 Inspect the installed CRDs

```sh
k get crd | grep cert-manager.io
# certificaterequests.cert-manager.io
# certificates.cert-manager.io
# challenges.acme.cert-manager.io
# clusterissuers.cert-manager.io
# issuers.cert-manager.io
# orders.acme.cert-manager.io
```

Look at one:
```sh
k get crd certificates.cert-manager.io -o yaml | less
k explain certificate.spec
```

Note how `kubectl explain` works on a CRD just like a built-in. The schema lives in the CRD.

## 8b.3 Create a self-signed Issuer + Certificate

```sh
k create ns lab8b
k config set-context --current --namespace=lab8b
```

`/tmp/issuer.yaml`:
```yaml
apiVersion: cert-manager.io/v1
kind: Issuer
metadata: { name: selfsigned, namespace: lab8b }
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata: { name: web-tls, namespace: lab8b }
spec:
  secretName: web-tls
  duration: 24h
  renewBefore: 12h
  commonName: web.lab8b.svc.cluster.local
  dnsNames:
    - web.lab8b.svc.cluster.local
  issuerRef:
    name: selfsigned
    kind: Issuer
```

```sh
k apply -f /tmp/issuer.yaml
```

## 8b.4 Watch reconciliation

```sh
k get certificate web-tls -o wide
# NAME      READY   SECRET    AGE
# web-tls   True    web-tls   12s

k get secret web-tls
# NAME      TYPE                DATA   AGE
# web-tls   kubernetes.io/tls   3      14s

k describe certificate web-tls    # see events: Issuing, Reused, etc.
```

The controller saw your Certificate CR, asked the Issuer to mint a cert, and produced the Secret. Pure reconcile pattern.

## 8b.5 Break the operator

```sh
k -n cert-manager scale deploy cert-manager --replicas=0
```

Now delete the Secret (simulate "oops"):

```sh
k delete secret web-tls
k get secret web-tls
# Error from server (NotFound)
```

The controller is down. The Certificate CR still says `Ready: True` but the Secret is gone. **Reconciliation depends on the controller running.**

Wait 30s — Secret stays missing. Check Certificate status:
```sh
k describe certificate web-tls
# (events from before still there, but nothing new)
```

## 8b.6 Bring the operator back

```sh
k -n cert-manager scale deploy cert-manager --replicas=1
k -n cert-manager get pods -w     # wait for Ready
```

Within ~30s, the controller re-reconciles and the Secret is recreated:

```sh
k get secret web-tls
# NAME      TYPE                DATA   AGE
# web-tls   kubernetes.io/tls   3      10s
```

This is the moral of CRDs + operators: the CR is desired state, the controller is what makes it happen. Lose the controller, lose the reconciliation.

## Cleanup

```sh
k delete ns lab8b
k delete -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml
```

(Skip the second line if other labs depend on cert-manager.)

## Deliverable

Show the trainer:
- `k get crd | grep cert-manager.io` — the installed CRDs
- `k describe certificate web-tls` events showing issuance
- The Secret disappearing when the controller is down, reappearing when it's back
