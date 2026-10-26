# Host Process Exhausts RAM: Reclaim-Thrash "Crash" With No OOM Kill

**Date:** 2026-09-25
**Machine:** 60 GiB RAM, 24 CPU threads, no swap at the time

## Summary

- **What happened:** the machine "crashed" twice within about 85 minutes. The first
  hang needed a hard power cycle. The second was a 12-minute SSH freeze that recovered
  on its own. Neither was a kernel panic or an OOM kill: `dmesg` was clean and the
  OOM-kill counter stayed 0.
- **Cause:** a developer test binary ran directly on the host, not in a container. It
  grew to 36.5 GB RSS within about 3 minutes (+18.4 GB per 30 s sample) and exhausted
  all RAM. The kernel never OOM-killed it: allocations kept succeeding by squeezing the
  page cache. The machine entered a direct-reclaim livelock (huge sys and iowait, load
  in the hundreds, SSH dead) where no out-of-memory event ever fires.
- **Fix:** run nothing heavy on the host outside containers. Put a memory limit on
  every container. For interactive work on the host, optionally run it in a systemd
  scope or slice with a memory limit.

## Timeline (condensed)

| Time | Event |
|------|-------|
| 09:20-09:23 | Test running: about one core of user CPU, load about 1.4. Looks normal on every dashboard. |
| 09:24:01 | Reclaim storm begins: sys 391%, iowait 221%. |
| 09:24:31 | Last atop sample of that boot: sys 1662%, iowait 528%. |
| 09:24-09:30 | atop logging gap of 6 min: the hang stopped even the atop daemon. No OOM kill, no panic, no SSH. Operator power-cycles. |
| 09:30 | New boot. wtmp shows no clean shutdown for the previous boot. |
| 10:33 | The test runs again. |
| 10:33-10:36 | Free memory 13.7 GB → under 500 MB. The test reaches 36.5 GB RSS, growing +18.4 GB per 30 s. |
| 10:37-10:49 | Livelock: free memory pinned at 340-480 MB; sys 521-1374%, iowait up to 1452%; load average peaks at 543; forks drop from 30/s to 0.2/s; SSH unresponsive. Some services restart after health-check timeouts. |
| 10:49:28 | The SSH session that started the test disconnects. |
| 10:49:31 | Session teardown kills the test: free memory 0.4 GB → 35 GB in one sample. The machine works again seconds later. |

## Why the OOM killer never fired

The OOM killer only acts when reclaim fails completely. With a multi-GB page cache that
almost never happens: each allocation succeeds by taking another piece of the page
cache. The system grinds instead of dying. `dmesg` stays clean and no process is
killed. With no swap and a large page cache, the result is a livelock, not an OOM kill.

`vm.panic_on_oom` does not cover this case, because no out-of-memory event ever fires.

## What the livelock looks like

- sys 521-1374% and iowait up to 1452% across 24 CPUs: about 14 cores in kernel reclaim
  and about 14 in iowait, while the runaway process itself used about 1.1 cores.
- Forks drop from 30/s to 0.2/s. Even `kill`, `top` or a new SSH shell cannot start.
  It feels like a hard crash, which is why the first hang needed a power cycle.
- Context switches rise from about 26k/s to 346k/s: threads churn on reclaim.
- The runaway grew +18.4 GB RSS in 30 s.
- The inference workers were victims, not the cause: their memory was shrinking as
  they lost page cache. The GPUs were fine.

## Telling the two hangs apart

- First hang: deep enough that atop stopped logging for 6 min. Needed a power cycle.
- Second hang: atop kept logging. The test died with its SSH session and about 35 GB
  came back within 3 s. Memory returning all at once is the sign that tells this apart
  from a hardware fault or a panic.

## Container limits do not protect against host processes

Memory limits on containers only bind the containers. A process started directly on the
host competes with every service and every container, and nothing limits it.

## Diagnosis with atop (no root needed)

The atop raw files (`/var/log/atop/atop_YYYYMMDD`, world-readable, 30 s samples)
held everything:

1. `atopsar -r <file> -b HH:MM -e HH:MM -c|-m|-p`: windowed reports. `-c` showed the
   sys/iowait storms, `-m` the pinned free memory and its sudden release, `-p` the load
   curve and the fork stall.
2. Both boots are in one daily file. The sample-time offset and the
   `logging restarted` marker separate them. A gap in the samples marks a hang deeper
   than the atop daemon.
3. `atop -r <file> -P PRC`: parseable per-process records; grep for a PID or name to
   find when it first appeared. A command name of the form `<package>.test` (cut to 15
   characters) marks a Go test binary, not a service.
4. Interactive replay (`atop -r <file>`, key `b` to jump to a time, `m` to sort by
   memory): RSIZE and RGROW per process at the storm sample named the culprit.
5. `last reboot`: duplicate "still running" entries are boots that never shut down
   cleanly, so a hard crash or power cycle.

False leads:

- `journalctl` is filtered by user ID for non-privileged users (note the "Hint" banner).
  The filtered journal suggested the previous boot ended the evening before; that was
  only the last message of the user's own session. Filtered journals can both invent
  and hide crashes.
- A large, busy-looking process was innocent: it was flat and calm all night. A suspect
  must be growing at the moment of exhaustion, not just big.
- Services restarting during the thrash were a symptom (health-check timeouts), not the
  cause.

## Detection gaps

- The monitoring stack fired nothing: there was no alert on host memory pressure (PSI
  or MemAvailable), and during the livelock the scrape path itself stalls.
- An alert cannot arrive in time for a 3-minute blowout. This class needs prevention
  (limits), not alerts.

## Prevention

1. Run nothing heavy on the host outside containers: not only AI/ML loads, but also
   tests, builds, benchmarks and data processing.
2. A memory limit on every container (`docker run --memory ... --memory-swap ...`).
3. For interactive work on the host, use a hard cgroup limit, for example
   `systemd-run --user --scope -p MemoryMax=8G <command>`, or `MemoryMax` on the user
   slice. If the limit is exceeded, the kernel OOM-kills only that scope; it works
   without swap. A test probe that allocated past a 256M scope limit was OOM-killed
   inside its scope and the machine never paused. `GOMEMLIMIT` is not a substitute: it
   is a soft GC target, and live references can push RSS far past it.
4. Optional extra layer: earlyoom. It polls MemAvailable and kills the largest process
   before memory is fully exhausted, and works without swap (systemd-oomd mostly acts
   on swap pressure). Set thresholds carefully and use `--avoid` for the serving
   processes.
5. Optional: an alert on host memory pressure. It helps with slow leaks but arrives too
   late for a fast blowout; never rely on it as the main control.
