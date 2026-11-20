# A Second Model Load Exhausts RAM and Swap: the Kernel Kills the Running Model Server

**Date:** 2026-11-20
**Hardware class:** multi-GPU inference host, about 60 GiB RAM, 10 GiB swap, models served by vLLM in containers
**Kernel setting at the time:** `vm.panic_on_oom = 0` (the kernel default)

## Summary

- **What happened:** a model server was running and healthy. Two minutes after a
  second container of another model server started on the same host, the kernel
  OOM killer killed the engine process of the **first**, running model server:

  ```text
  kernel: oom-kill:constraint=CONSTRAINT_NONE ... global_oom
  kernel: Out of memory: Killed process <pid> (VLLM::EngineCor) total-vm:2079996496kB,
          anon-rss:77580kB, file-rss:28182476kB ...
  kernel: Free swap  = 136kB
  kernel: Total swap = 10485756kB
  ```

  The container of the killed server exited with code 1. For about 9 seconds the
  platform's control plane did not answer on the same host.
- **Cause:** both servers read their model weights (about 95 GB each) from disk. The
  weights are memory-mapped, so the pages count as the process's resident memory
  (`file-rss` above), and a loading server also needs anonymous memory. Together the
  two exhausted RAM and the whole swap. Container memory limits did not help: each
  container had a 48 GB limit, which is a cgroup limit, and the two limits together
  were larger than the host's RAM, so the out-of-memory event was host-wide
  (`global_oom`), where cgroup limits do not apply. The kernel killed the process
  with the highest score, which was the running server, not the one that was loading.
- **With the S2 settings** ([04](../04-provisioning.md), Phase 4: `vm.panic_on_oom = 1`)
  the same event would not have killed one model server: it would have panicked the
  host and rebooted it, with every model on it down.
- **Fix:** run `earlyoom` ([04](../04-provisioning.md), Phase 4, "Kill a model server
  before the host runs out of memory"): it acts when available memory and available
  swap are both at or below 5 %, before the kernel's own out-of-memory handling, and
  kills the model server's engine process first. And never start a second model server
  on a host while another one is loading or serving: wait until the first one is
  healthy and check `free -h` first.

## Check

```sh
journalctl -k | grep -i -E 'out of memory|oom-kill'    # earlier kills
systemctl is-active earlyoom                           # active
journalctl -u earlyoom -n 5                            # "sending SIGTERM when mem avail <= 5.00% and swap free <= 5.00%"
```

## How `earlyoom` was tested

With the production settings and the threshold raised for the test, three dummy
processes were started: one named like the vLLM engine process (`VLLM::EngineCor`,
4 GB), one named like the container engine (`dockerd`, 0.8 GB) and one with another name
(0.8 GB). When available memory fell below the test threshold, `earlyoom` sent SIGTERM
to the one named like the engine, which exited after 0.1 seconds. The other two and
the real services (database, container engine, SSH, the node service) were left
alone. The service runs as a dynamic user: this also showed that it may stop a process
owned by root. After the test the threshold went back to 5 %.

## References

- earlyoom: <https://github.com/rfjakob/earlyoom> (`--prefer`, `--avoid`, `-m`, `-s`)
- [260925](260925-host-test-memory-exhaustion-thrash-crash.md): a host-wide memory
  thrash where no out-of-memory event fired at all
