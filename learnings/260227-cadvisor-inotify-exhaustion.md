# inotify instance exhaustion by a monitoring container

Date: 2026-02-27
OS: Ubuntu 24.04, kernel 6.17.0-14-generic

**Summary.** A cAdvisor container (`gcr.io/cadvisor/cadvisor:v0.51.0`) used up the inotify instances of user root (UID 0). After that, the NVIDIA GPU device plugin, also running as root, could not create a file watcher and failed at startup with `too many open files`. Cause: the kernel default `fs.inotify.max_user_instances = 128` is shared by all processes of one UID, and monitoring and container tooling need more. Fix: raise `fs.inotify.max_user_instances` to 1024 and `fs.inotify.max_user_watches` to 1048576 in `/etc/sysctl.d`, and prefer monitoring that uses the Docker API instead of inotify.

## Symptoms

The GPU device plugin crashed and restarted in a loop with:

```
Starting FS watcher for <device-plugin directory>
failed to create FS watcher for <device-plugin directory>/: too many open files
```

The error came within microseconds of startup, so the quota was already exhausted before the process started. "too many open files" here means the inotify limit, not the file descriptor limit (`ulimit -n`).

## Root cause

- Linux counts inotify instances per user (UID). All processes of the same UID share the quota, also across containers. The default limit is 128 instances.
- cAdvisor runs as root with broad host access (`/`, `/var/run`, `/sys`, `/var/lib/docker`, `/dev/disk` mounted read-only) and watches containers and cgroups with inotify.
- Any other root process that needs a new inotify instance then fails.

Tests while cAdvisor was running:

| Test | Result |
|------|--------|
| Host, as UID 1000 | 120 instances created before hitting the limit |
| Container, as UID 0 | 0 instances, immediate failure |
| Container, as UID 1000 | Success |
| Container, as UID 0, cAdvisor stopped | Success |

So only the quota of UID 0 was exhausted.

## Fix

Raise the limits persistently:

```bash
cat <<'EOF' | sudo tee /etc/sysctl.d/90-inotify.conf
fs.inotify.max_user_instances = 1024
fs.inotify.max_user_watches = 1048576
EOF
sudo sysctl --system
```

Immediate workaround: stop the offending container (`docker rm -f cadvisor`). The device plugin then started normally.

For Docker container metrics, the OpenTelemetry Collector `docker_stats` receiver is an alternative to cAdvisor. It reads CPU, memory and network I/O per container from the Docker API and uses no file watchers.

## Verify

```bash
# Current limits
sysctl fs.inotify.max_user_instances fs.inotify.max_user_watches

# Number of inotify instances per process (largest first)
sudo find /proc/*/fd -lname 'anon_inode:inotify' 2>/dev/null \
  | cut -d/ -f3 | sort | uniq -c | sort -rn | head
```

## References

- [Kernel docs: inotify](https://www.kernel.org/doc/html/latest/filesystems/inotify.html)
- [cAdvisor on GitHub](https://github.com/google/cadvisor)
