# Pre-Course Setup — Required Before Day 1

You'll be working on a **Debian 13 VM** the trainer provisions for you. It
arrives with Docker, kubectl, Helm, kind, and the course repo already
installed. You don't have to install anything yourself.

**What you DO have to do before Day 1:**

1. **Confirm you can SSH / RDP / connect** to your assigned Debian VM. The
   trainer will email you connection details 2 days before the course. If
   you can't connect by the day before, message the trainer.
2. **Work through `docker-primer.md` (2-3 h, mandatory).** See section 2
   below.
3. **Work through `linux-primer.md` (1-2 h, mandatory).** Section 3.
4. **Do 30 minutes of `vimtutor`.** The exam runs in a terminal with vim.
   Mac/Windows developers especially: don't skip this.

The course is intensive. Showing up under-prepared costs you the morning of
Day 1 and you never quite catch up. **Do every section of this document
before the first day.**

---

## 1. Your machine

The trainer will assign you a Debian 13 VM with at least:

- 15 GB RAM
- 8 vCPU threads
- 50 GB disk
- Nested virtualization not required (we use kind for the cluster, not nested VMs)

You connect to it via the desktop access method the trainer specifies
(typically through dadesktop). All work happens on this VM. Your laptop is
just a thin client.

If you have access concerns (corporate firewall blocking RDP, missing
credentials, etc.), **resolve them with the trainer 2 days before**, not on
Day 1 morning.

---

## 2. Mandatory pre-work — Docker / containers primer

If you have a knowledge gap, **it is here.** Work through
[`docker-primer.md`](./docker-primer.md) before Day 1. Budget 2–3 hours.

You can do the conceptual sections (1, 2) anywhere. For the hands-on (3-8),
either:
- Install Docker on your personal laptop, OR
- Wait for your Debian VM access (Docker is pre-installed there).

You need to leave the primer able to:

- Explain what a container is (Linux namespaces + cgroups + a layered filesystem).
- Run `docker run`, `docker exec -it`, `docker logs`, `docker ps`.
- Read a Dockerfile and explain `FROM`, `RUN`, `COPY`, `ENTRYPOINT`, `CMD`.
- Distinguish image vs container, layer vs filesystem, registry vs local image cache.
- Use `docker exec sh` to poke inside a running container.

If those bullets feel uncomfortable, **do the primer before Day 1.** This
matters more than anything else.

---

## 3. Linux fundamentals refresher

You'll be in a Linux shell most of the week, and the exam itself is one too.
Mac and Windows trainees especially: read [`linux-primer.md`](./linux-primer.md)
and verify you're comfortable with:

- `systemctl status / start / restart / enable <service>`
- `journalctl -u <service> -n 100 --no-pager`
- `ss -tlnp` / `ip addr` / `ip route`
- `ps aux | grep` / `pgrep` / `kill -<sig>`
- File permissions (`chmod`, `chown`), basic users/groups
- `vim` survival: `i`, `:wq`, `:q!`, `dd`, `yy`, `p`, `/`, `:set paste`

You can practice on your Debian VM once you have access. Or on any local
Linux box. Or in a free Ubuntu container locally.

---

## 4. What's pre-installed on your VM

Don't worry about installing anything. When your VM is ready, the
following will all work out of the box:

```sh
docker version                # Docker Engine ≥ 24
kubectl version --client      # 1.36.x
helm version                  # v4.2.0
kind version                  # v0.31+

# Course repo cloned at ~/cka-intensive (or your home dir; trainer will say)
ls ~/cka-intensive
```

Shell hygiene is already set up in `~/.bashrc`:

```sh
alias k=kubectl
source <(kubectl completion bash)
complete -F __start_kubectl k
export do='--dry-run=client -o yaml'
export now='--grace-period=0 --force'
```

---

## 5. First thing on Day 1

After we open the room and do exam logistics, you'll bootstrap the cluster:

```sh
cd ~/cka-intensive/infra/scripts
./kind-bootstrap.sh
./verify-cluster.sh
```

About 3 minutes. You'll have a 3-node Kubernetes cluster on your VM. Then
we start Lab 1.

Detailed walkthrough: [`vm-setup.md`](./vm-setup.md).

---

## 6. Accounts to create (free)

- [killercoda.com](https://killercoda.com) — free browser labs for evening homework
- [linuxfoundation.org training portal](https://trainingportal.linuxfoundation.org/) — where you'll book the exam (don't book until ~2 weeks after the course)

---

## 7. What you'll have at the end of pre-course

✅ Working access to your Debian VM
✅ Containers as a concept you actually understand
✅ Basic Linux shell fluency
✅ Familiarity with vim's survival commands

You'll arrive on Day 1 ready to **learn Kubernetes**, not "figure out the
installer."
