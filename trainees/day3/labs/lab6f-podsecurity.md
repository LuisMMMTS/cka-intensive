# Lab 6f — Pod Security Admission

**Time:** 20 min
**Goal:** apply PSA to a namespace, watch it reject an unhardened Pod, then harden the Pod until it's admitted.

Work in namespace `lab6f`:
```sh
k create ns lab6f
```

---

## 6f.1 Enforce `restricted` on the namespace

```sh
k label ns lab6f \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/enforce-version=v1.36 \
  pod-security.kubernetes.io/warn=restricted \
  pod-security.kubernetes.io/audit=restricted
```

Confirm:

```sh
k get ns lab6f --show-labels
```

---

## 6f.2 Try to deploy plain nginx

```sh
k -n lab6f run nginx --image=nginx:1.27
```

You should see a rejection. The message names exactly which policy violations were detected:

```
Error from server (Forbidden): pods "nginx" is forbidden:
violates PodSecurity "restricted:v1.36":
allowPrivilegeEscalation != false (container "nginx" must set ...),
unrestricted capabilities (container "nginx" must set ...),
runAsNonRoot != true (pod or container "nginx" must set ...),
seccompProfile (pod or container "nginx" must set ...)
```

Read the message carefully — that's the to-do list.

---

## 6f.3 Harden until accepted

Generate the YAML:

```sh
k -n lab6f run nginx --image=nginx:1.27 $do > /tmp/nginx.yaml
```

Edit `/tmp/nginx.yaml`. Replace the auto-generated `spec` with:

```yaml
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 101              # nginx user inside the image
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: nginx
      image: nginxinc/nginx-unprivileged:1.27   # the official root-free variant
      ports:
        - containerPort: 8080
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop: [ALL]
        readOnlyRootFilesystem: true
      volumeMounts:
        - { name: cache, mountPath: /var/cache/nginx }
        - { name: run,   mountPath: /var/run }
  volumes:
    - name: cache
      emptyDir: {}
    - name: run
      emptyDir: {}
```

Apply:

```sh
k apply -f /tmp/nginx.yaml
k -n lab6f get pod nginx
```

Three things you changed:

1. **Image:** `nginx:1.27` runs as root; `nginxinc/nginx-unprivileged:1.27` doesn't.
2. **securityContext:** added all four fields PSA's `restricted` checks for.
3. **readOnlyRootFilesystem:** required `emptyDir` mounts for nginx's writable paths.

---

## 6f.4 Compare to `baseline`

```sh
k create ns lab6f-baseline
k label ns lab6f-baseline pod-security.kubernetes.io/enforce=baseline
k -n lab6f-baseline run nginx --image=nginx:1.27   # accepted (with a warning)
```

`baseline` is much more permissive — it blocks the worst (host paths, host network, privileged) but tolerates root containers and missing seccomp.

---

## 6f.5 The warn-only pattern (recommended rollout)

In production you don't flip a namespace to `enforce: restricted` overnight. You set:

```sh
k label ns my-ns --overwrite \
  pod-security.kubernetes.io/warn=restricted \
  pod-security.kubernetes.io/audit=restricted
# (no enforce yet)
```

Now every Pod that *would have* been rejected emits a warning to the user creating it and an audit log entry. You watch for ~2 weeks, fix the warnings, then flip enforce on.

---

## Cleanup

```sh
k delete ns lab6f lab6f-baseline
```

## Deliverable

Show the trainer:
- The rejection on the plain `nginx:1.27` Pod
- A Running `nginx` Pod in the `restricted` namespace with the hardened spec
- `k get pod nginx -o jsonpath='{.spec.securityContext}{.spec.containers[0].securityContext}'`

## CKA exam relevance

PSA is **in the curriculum but rarely the focus of a whole question.** It appears as a side-constraint: "create a Pod that runs in this namespace [which has a `restricted` label]." Knowing the four required fields cold means it's a free 4-5%, not a 10-minute fight.
