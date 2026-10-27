# Scripts

The runbook's steps as scripts, in order. Copy the folder to the machine and run each
one **as root** (`sudo bash <script>`) in the shared tmux session
([CLAUDE.md](../CLAUDE.md)). Each is safe to run again; each prints what it did and
stops at the first real problem. Logs go to the home of the user who ran `sudo`.

Rocky Linux 10 only for now; on Ubuntu 24.04 follow the runbook's Ubuntu blocks.

| Order | Script | Runbook | Attended? |
|---|---|---|---|
| 1 | `provision-phases-2-4.sh` | [04](../04-provisioning.md) Phases 2 to 4: updates, inventory, NVIDIA driver, kernel parameters | Yes: may stop for a reboot (new kernel); Secure Boot must be off ([03](../03-bring-up.md)) |
| 2 | reboot | | |
| 3 | `provision-phase-5.sh` | [04](../04-provisioning.md) Phase 5: Docker, NVIDIA Container Toolkit | Short |
| 4 | `provision-phase-6-fan2go-build.sh` | [04](../04-provisioning.md) Phase 6: sensors, fan2go built for Rocky, `fan2go detect`, fan RPMs | Short; then the fan unplug test by hand |
| 5 | `provision-phase-6-fan2go-config.sh` | [04](../04-provisioning.md) Phase 6: configuration and service | About 2 minutes (fan measurement) |
| 6 | `host-checks.sh` | [05](../05-acceptance.md) section 2 | Short: PASS/FAIL list |
| 7 | `accept-gpu-thermal.sh` | [05](../05-acceptance.md) GPU thermal, 10 minutes | Watch it |
| 8 | `accept-short.sh` | [05](../05-acceptance.md) disk health and a short run of every long test | About 3 minutes |
| 9 | `accept-long.sh` | [05](../05-acceptance.md) memory, disks, GPU stability | No: hours, unattended |

Hands-on tests (power loss, BMC power cycle, network failover) have no script: they
need a person at the machine.
