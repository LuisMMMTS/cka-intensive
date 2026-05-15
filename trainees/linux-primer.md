# Linux Fundamentals Primer

**Budget: 1–2 hours.** Do this before Day 1, especially if you're a Mac or
Windows developer who rarely SSHs into Linux.

Day 4 is **30% of the exam: troubleshooting.** All of it happens at a shell
prompt inside a Linux VM. If `systemctl`, `journalctl`, and `ss` are foreign
to you, troubleshooting day will be a wall.

This is not a Linux course — it's the smallest set of commands you need to
read the exam's symptoms.

---

## 1. Where to practice

You don't need to install anything special — your Debian VM **is** Linux,
so you can practice the commands directly in your shell.

If you want to play in an isolated environment so you don't risk breaking
the VM, run a throwaway Docker container:

```sh
docker run --rm -it debian:13 bash
apt-get update && apt-get install -y systemd procps iproute2 vim less
# (some commands need systemd, which doesn't run in a normal Docker
#  container — for those, just practice on your Debian VM directly)
exit
```

Or just practice on your Debian VM — everything in this primer is
read-only or trivially reversible.

---

## 2. systemd — services on a modern Linux

`systemd` is what manages services (daemons) on Ubuntu, RHEL, Debian, basically
everything but Alpine. The kubelet is a systemd service. So is containerd. So
is sshd. **You will manage all of these on Day 4.**

```sh
# Status
sudo systemctl status kubelet            # is it running? when did it (re)start? recent log lines
sudo systemctl status sshd

# Lifecycle
sudo systemctl start kubelet             # one-off start
sudo systemctl stop kubelet
sudo systemctl restart kubelet           # stop then start
sudo systemctl reload kubelet            # ask the service to re-read its config (most don't support)

# At-boot
sudo systemctl enable kubelet            # start automatically at boot
sudo systemctl disable kubelet
sudo systemctl is-enabled kubelet

# The "is it broken" gotcha
sudo systemctl is-failed kubelet         # 'failed' / 'active' / 'inactive'
sudo systemctl mask kubelet              # PREVENT it from being started, even manually
sudo systemctl unmask kubelet            # undo a mask

# Where's the unit file?
systemctl cat kubelet                    # shows the unit file contents
systemctl show kubelet -p ExecStart      # show one property
```

**Day 4 Lab 9 will hand you a kubelet that's been `systemctl mask`-ed** — the
question is whether you'll recognize that from `systemctl status`. The output
says `Loaded: masked` and `Active: inactive (dead)`. Memorize the look of it.

---

## 3. journalctl — the logs

systemd captures every service's stdout/stderr into the **journal**. Forget
`tail -f /var/log/syslog`; on modern Linux you read journalctl.

```sh
# A service's logs
sudo journalctl -u kubelet               # all of it, pageable
sudo journalctl -u kubelet -n 100        # last 100 lines
sudo journalctl -u kubelet --no-pager    # no `less` wrapping, dump it
sudo journalctl -u kubelet -f            # follow (like tail -f)
sudo journalctl -u kubelet --since "10 min ago"
sudo journalctl -u kubelet -p err        # only error-priority and worse

# Boot-scoped
sudo journalctl -b                       # logs since this boot
sudo journalctl -b -1                    # logs from previous boot
sudo journalctl -k                       # kernel ring buffer (dmesg)
```

**Day 4 muscle memory:**

```sh
sudo journalctl -u kubelet -n 100 --no-pager | tail -50
```

That is the first command you run when a node goes NotReady. Read the last 50
lines for: "failed to pull image", "container runtime is down", "node not
found", "certificate expired", "no space left on device". The kubelet will
*tell* you what's wrong.

---

## 4. Process inspection

```sh
ps aux                                   # all processes, BSD-style output
ps -ef                                   # all processes, SysV-style
ps auxf                                  # forest/tree view (parent-child)

pgrep -af kubelet                        # find PIDs matching, show full cmdline
pgrep -P 1                               # children of PID 1 (init)

# Signal a process
kill <pid>                               # SIGTERM (graceful, default)
kill -9 <pid>                            # SIGKILL (rude, no cleanup)
kill -HUP <pid>                          # SIGHUP (commonly: reload config)
killall nginx                            # by name (use carefully)

# What is this process actually doing?
sudo cat /proc/<pid>/cmdline | tr '\0' ' '   # full command line with args
sudo ls -l /proc/<pid>/fd                    # what files/sockets is it holding open?
sudo cat /proc/<pid>/status                  # memory, threads, uid
```

In containerland: the kubelet kills containers with SIGTERM, waits
`terminationGracePeriodSeconds` (default 30s), then SIGKILL. The probes Day 1
covers are about getting the SIGTERM at the right time.

---

## 5. Networking inspection

You will not configure networks on the exam — but you'll read them. Three
commands cover 90% of what you need:

```sh
# What's listening, and which process?
sudo ss -tlnp                            # TCP, listening, numeric ports, processes
sudo ss -tunap                           # TCP + UDP, all states, with processes
sudo ss -tnp state established           # active TCP connections

# What addresses does this host have?
ip addr                                  # all interfaces, all IPs
ip -br addr                              # brief one-line-per-interface
ip route                                 # routing table
ip route get 8.8.8.8                     # which interface would go to 8.8.8.8?

# DNS
nslookup kubernetes.default              # name → IP (and back)
dig @10.96.0.10 kubernetes.default.svc.cluster.local +short
getent hosts cluster-name                # what does the system resolve to?
```

**Day 2 + Day 4 lesson:** Service VIPs (e.g., `10.96.0.1`) don't have an
interface. They're virtual IPs that kube-proxy turns into iptables/nftables
rules. `ss` won't show anything listening on them. `curl` works anyway because
the kernel rewrites the destination. This catches people every time.

---

## 6. Files and permissions

```sh
ls -l                                    # readable size, mtime, perms, owner
ls -la                                   # include dotfiles
ls -lh                                   # human-readable sizes

# Permissions
chmod 644 file                           # rw-r--r--
chmod +x script.sh                       # add execute
chown root:root /etc/foo                 # set owner + group

# Find
find /etc/kubernetes -name '*.yaml' -type f
find / -size +100M 2>/dev/null           # files bigger than 100M (quiet)
```

Permission disasters on Day 4 you might see:
- Kubelet can't read kubeconfig because someone `chmod 600`-ed it as a different user.
- `kubectl` returns "permission denied" reading `/etc/kubernetes/admin.conf` because you're not root and the file is `mode 600 root:root`.

The fix is usually obvious from `ls -l` plus knowing what user you are
(`id`).

---

## 7. Disk + space

```sh
df -h                                    # filesystems and free space, human-readable
df -i                                    # inodes (you can be out of inodes with 90% free space)
du -sh /var/lib/etcd                     # how big is this directory?
du -sh /var/log/* | sort -h              # which subdir is biggest?
```

The exam scenario: kubelet starts logging "no space left on device" — `df -h`
shows you /var is full — `du -sh /var/log/*` shows journald has grown to 10GB
— fix is `sudo journalctl --vacuum-size=200M`.

---

## 8. Editors — vim, the unavoidable

The exam **does not have VS Code**. There's a terminal. There's vim. Make
peace with it.

Minimum survival kit:

```
i           insert mode (start typing)
ESC         back to command mode
:w          save
:q          quit (only if no unsaved changes)
:wq         save and quit
:q!         quit without saving (lose changes)
:set paste  paste mode (turns off auto-indent before you paste YAML)
:set nu     show line numbers
dd          delete current line
yy          copy (yank) current line
p           paste below
u           undo
Ctrl-r      redo
/word       search forward for 'word'
:%s/a/b/g   replace all 'a' with 'b' in the whole file
gg          go to top
G           go to bottom
:42         go to line 42
```

Type `vimtutor` from any Linux shell — it's a 30-minute interactive tutorial.
Do it. Once. You will thank yourself on exam day.

**YAML tip:** before you paste a multi-line YAML block into vim, type
`:set paste` first. Otherwise vim's auto-indent will mangle the indentation
and your YAML won't parse. After pasting, `:set nopaste` to restore.

---

## 9. Quick-look exercises

In a Multipass VM:

1. Find which process is listening on port 10250. (`ss -tlnp | grep :10250` → kubelet)
2. Show the last 20 lines of kubelet's logs. (`sudo journalctl -u kubelet -n 20 --no-pager`)
3. The kubelet is "failed." `mask`-it, then notice the difference in `systemctl status` output. Then `unmask` and `start`.
4. Find all files under `/etc/kubernetes` modified in the last day. (`find /etc/kubernetes -mtime -1`)
5. Show the IP of the default route. (`ip route | awk '/^default/ {print $3}'`)
6. Edit `/etc/hosts` with vim, add a line `127.0.0.1 demo.local`, save, exit, and `getent hosts demo.local` should return `127.0.0.1`.

If you can do all six in 5 minutes, you're ready for Day 4 troubleshooting.

---

## Reference card — print and bring

```
SERVICES   sudo systemctl {status|start|stop|restart|enable|disable|mask|unmask} <svc>
LOGS       sudo journalctl -u <svc> [-n N] [-f] [--since "10 min ago"]
PROCESSES  ps auxf | pgrep -af <name> | kill [-9|-HUP] <pid>
NETWORK    sudo ss -tlnp | ip [-br] addr | ip route | nslookup <name>
DISK       df -h | du -sh /path | sudo journalctl --vacuum-size=200M
EDIT       vim: i / ESC / :wq / :q! / dd / yy / p / :%s/a/b/g / :set paste
```
