# Docker / Containers Primer — Mandatory Pre-Course

**Budget: 2–3 hours.** Do this before Day 1.

The course assumes you know what a container is. If you've never run `docker
run` before, this primer fixes that. If you've used Docker casually, **still
read sections 1 and 2** — the mental model matters more than the commands.

You don't need Docker installed for sections 1–2 (they're conceptual). For 3–8
you'll need Docker Desktop (or Podman) on your laptop.

---

## 1. What a container actually is

Forget the whale logo for a minute. A container is not a special kind of file
or a tiny VM. **It's a normal Linux process** that the kernel has been told to
lie to about three things:

| What | Mechanism | What it means |
|------|-----------|---------------|
| What's in the filesystem  | mount namespace + overlayfs | The process sees a different root `/` than the host. |
| What other processes exist | PID namespace | `ps` inside shows only the process's own tree (PID 1 is the container's entrypoint). |
| What the network looks like | network namespace | The process gets its own loopback, interfaces, routing table. |
| How much CPU/RAM it can use | cgroups (v2) | Kernel enforces limits — exceed memory limit, you get OOM-killed. |
| Which users exist          | user namespace (optional) | UID 0 inside the container can be UID 1000 on the host. |

A running container is **just a process** with namespaces and cgroups applied.
On Linux:

```
# host
ps aux | grep nginx
1000     12345  ... nginx: master process     ← the container's process is right there
ls /proc/12345/ns/                            ← these symlinks ARE the namespaces
  ipc -> ipc:[4026531839]
  mnt -> mnt:[4026532245]
  net -> net:[4026532247]
  pid -> pid:[4026532246]
  user -> user:[4026531837]
  uts -> uts:[4026532244]
```

Two containers from the same image are two processes with **different
namespace IDs but identical contents**. If you stopped using containers
tomorrow and ran the same processes with `unshare` and `cgcreate` directly,
you'd have the same thing. Docker is a developer-friendly wrapper over kernel
primitives that already existed.

**Why this matters for Kubernetes:** when we say "a Pod is a group of
containers sharing a network namespace," now you know what that *means*. They
share `ns/net` so they see each other on `localhost`; they don't share `ns/mnt`
so they each have their own filesystem; they share `ns/ipc` so they can talk
via SystemV/POSIX IPC.

---

## 2. Images, layers, and how containers start

An **image** is a stack of read-only filesystem layers plus a JSON manifest
that says "use these layers, set this entrypoint, listen on these ports, run as
this user." It's not an executable in any traditional sense.

```
┌──────────────────────────────────────┐
│ image: nginx:1.27                    │
│  ┌────────────────────────────────┐  │
│  │ layer 4: /etc/nginx/nginx.conf │  │   ← top, "smallest" — the customization layer
│  ├────────────────────────────────┤  │
│  │ layer 3: nginx package files   │  │
│  ├────────────────────────────────┤  │
│  │ layer 2: apt cache + libraries │  │
│  ├────────────────────────────────┤  │
│  │ layer 1: debian:bookworm rootfs│  │   ← base, big
│  └────────────────────────────────┘  │
│  config: ENTRYPOINT ["nginx"]        │
│          CMD ["-g", "daemon off;"]   │
│          EXPOSE 80                   │
└──────────────────────────────────────┘
```

Each layer is a tarball of file changes. When you run the container, the
runtime stacks the layers via **overlayfs** and gives the process a unified
view of `/`. Writes go to a writable top layer that exists only for the life
of this container — kill the container, the writes vanish.

This is why two containers from `nginx:1.27` together take ~25 MB extra (each
gets its own writable layer), not 2× the image size.

A **registry** (Docker Hub, GHCR, ECR, GAR) stores images. `docker pull
nginx:1.27` fetches each layer not already in the local cache. **A tag is just
a pointer to a digest** — `nginx:1.27` today may point at a different digest
tomorrow. For real reproducibility you use the digest:
`nginx@sha256:abc123...`.

---

## 3. Set up

Install Docker Desktop (mac/windows) or Docker Engine (Linux):

```sh
# macOS
brew install --cask docker
open -a Docker     # launch it, accept the license

# Linux
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER && newgrp docker

# Verify
docker version
docker run --rm hello-world
```

You should see "Hello from Docker!" — that confirms the daemon is up, the
local image cache works, and the kernel can run containers.

---

## 4. Run, exec, log, inspect

Run an interactive container:

```sh
docker run --rm -it ubuntu:22.04 bash
# now you're inside; explore:
ps aux              # only bash and ps; that's the whole container
hostname            # random ID, not your laptop's hostname
cat /etc/os-release # Debian/Ubuntu inside, regardless of your host OS
ip addr             # different interfaces than your host
exit                # container dies (--rm cleans it up)
```

Run something in the background:

```sh
docker run -d --name web -p 8080:80 nginx:1.27
# -d   detached (background)
# -p   publish port: laptop:8080 → container:80

docker ps                          # see it running
curl http://localhost:8080         # nginx welcome page
docker logs web                    # see what nginx printed
docker exec -it web bash           # open a shell inside the running container
  cat /etc/nginx/conf.d/default.conf
  ls /usr/share/nginx/html
  exit
docker stop web && docker rm web   # clean up
```

`exec` runs a new process **inside an existing container's namespaces**. `run`
creates a new one. Useful Kubernetes mental hook: `kubectl exec` is exactly
this — a process in the pod's namespaces.

Inspect what an image actually contains:

```sh
docker pull alpine:3.20
docker inspect alpine:3.20 | less   # JSON with layers, env, cmd, entrypoint
docker image history alpine:3.20    # layer-by-layer with sizes
```

---

## 5. Build an image

Create a directory:

```sh
mkdir hello-app && cd hello-app
```

`app.sh`:

```sh
#!/bin/sh
echo "hello from container, args: $@"
echo "PID 1 inside container is $$"
sleep 600
```

`Dockerfile`:

```dockerfile
FROM alpine:3.20                     # base image (1 layer)
RUN apk add --no-cache curl          # install curl (new layer)
WORKDIR /app                         # mkdir + cd
COPY app.sh /app/app.sh              # copy from build context (new layer)
RUN chmod +x /app/app.sh             # make executable (new layer)

# These are metadata, not layers:
USER nobody                          # process won't run as root
EXPOSE 8080                          # documentation only
ENTRYPOINT ["/app/app.sh"]           # fixed; CMD adds default args
CMD ["world"]                        # default arg, overridable at run time
```

Build and run:

```sh
docker build -t hello:0.1 .
docker run --rm hello:0.1            # → "hello from container, args: world"
docker run --rm hello:0.1 luis       # → "hello from container, args: luis"
docker image history hello:0.1       # see all 5 layers + their sizes
```

**ENTRYPOINT vs CMD trap** — appears in CKA morning quizzes:

| Dockerfile | `docker run img foo bar` runs |
|---|---|
| `ENTRYPOINT ["x"]` only | `x foo bar` |
| `CMD ["x"]` only | `foo bar` (CMD overridden entirely) |
| Both | `entrypoint cmd_overridden_by_args` |

In Kubernetes pod spec, `command:` overrides ENTRYPOINT and `args:` overrides
CMD. **Same trap.**

---

## 6. Push to a registry (optional)

```sh
docker login                                              # auth to Docker Hub
docker tag hello:0.1 yourusername/hello:0.1
docker push yourusername/hello:0.1
```

For the CKA course you won't push; you'll pull from public registries. But
knowing the round-trip makes ImagePullBackOff errors easier to read on Day 1.

---

## 7. Networking (just enough)

By default, Docker creates a bridge network and gives each container an IP.
Containers on the same network can reach each other by name:

```sh
docker network create demo
docker run -d --name db   --network demo postgres:16 -c log_min_messages=panic
docker run --rm --network demo postgres:16 psql -h db -U postgres -c '\l' || true
# (will fail auth, but the DNS resolution and TCP connect worked)
docker rm -f db
docker network rm demo
```

This is the seed of how Kubernetes Services work — only k8s does the DNS
across the whole cluster, not just one Docker network.

---

## 8. Mental-model exercises (do these — they unlock Day 1)

Answer in your head, then verify with the command.

1. You run `docker run -d --name x nginx:1.27`. Run `docker exec x ps -ef`. How many processes do you expect to see, and which is PID 1?
2. Run `docker run --rm -d --name y nginx:1.27`. Then `docker stop y`. What happens to the writable layer's contents?
3. Run `docker run --rm -it --memory=50m alpine sh`, then inside: `dd if=/dev/zero of=/big bs=1M count=200`. What happens, and why?
4. You have `IMAGE_A` with ENTRYPOINT `/bin/echo` and CMD `hello`. What does `docker run IMAGE_A world` print? What does it print if you run with `--entrypoint /bin/date IMAGE_A`?
5. Two containers from the same image — do they share memory? Do they share files? Why or why not?

### Answers (peek after trying)

<details>
<summary>1. PID 1 = nginx master process; you'll see nginx workers as children. ps inside the container only sees the container's own PID namespace, not the host.</summary>
</details>

<details>
<summary>2. The writable layer is destroyed (—rm wasn't even needed; `stop` keeps it but `rm` deletes it; without —rm the file would survive `stop` and reappear on `docker start y`). The image layers below are untouched and reused.</summary>
</details>

<details>
<summary>3. dd is killed by the kernel's OOM killer (cgroup memory limit exceeded). The shell stays open, but `dmesg | tail` on the host shows the OOM event. This is exactly what happens to a Kubernetes container that exceeds its memory `limits`.</summary>
</details>

<details>
<summary>4. First: "hello world" (ENTRYPOINT="echo" + CMD="hello" overridden by arg "world" → echo world; actually echo hello world if CMD is appended… verify with `docker inspect` — depends on JSON-array vs shell form). Second: runs date instead of echo. `--entrypoint` overrides ENTRYPOINT entirely.</summary>
</details>

<details>
<summary>5. They share image layers on disk (one copy of each layer, mounted into both via overlayfs). They do NOT share memory (different processes, different mm structs in the kernel). They do NOT share files in writable space (each has its own top layer).</summary>
</details>

---

## What you should be able to do after this primer

- Run a container interactively and detached
- `exec` into a running container to debug it
- Read a Dockerfile and predict what the resulting image will do
- Distinguish image / container / layer / registry without flinching
- Explain the ENTRYPOINT vs CMD interaction in two sentences
- Understand why "a container is just a process" makes Kubernetes' mental model land

If any of these still feels shaky, do the section again. **Coming into Day 1
shaky on containers is the single largest predictor of struggling all week.**

---

## Beyond Docker

Kubernetes does not run Docker — it runs `containerd` or CRI-O directly via
the **Container Runtime Interface (CRI)**. Docker is what you used to build
the image. Once the image is in a registry, the cluster's runtime pulls it via
the same OCI standard. **The image format is identical.** This is why you can
build with Docker on your laptop and run on a Kubernetes cluster that has
never heard of Docker.

You'll see this in detail on Day 1.
