# Scripts

The runbook's steps as scripts, in order. Copy the folder to the machine
(`~/s2-scripts/`) and run them through **`run.sh`**, as the admin user, in the shared
tmux session ([CLAUDE.md](../CLAUDE.md)):

```sh
bash ~/s2-scripts/run.sh phases-2-4                               # then reboot
bash ~/s2-scripts/run.sh phase-5 fan2go-build                     # then the fan unplug test
bash ~/s2-scripts/run.sh fan2go-config aide host-checks gpu-thermal accept-short
bash ~/s2-scripts/run.sh accept-long                              # unattended, hours
```

`run.sh` asks for the `sudo` password **once** and keeps `sudo` alive for every step
of the call (no 5-minute timeout between them), runs each step as root with absolute
paths, writes one log per step to `~/s2-logs/`, carries on after a failed step and
ends with one summary. Do not call the scripts with `sudo bash -c "..."` yourself:
inside it `~` is root's home and the scripts are not found. Each is safe to run again; each prints what it did and
stops at the first real problem.

Every script is **self-contained**: it installs or creates everything it uses itself, or,
when it needs an earlier script's result (the driver, fan2go), stops at once with
`STOP: ... run <script> first`. It never relies on a manual step or on what happened to
be on the machine where it was written. Test a changed script on a machine that has
not seen it, or check each command's prerequisites by reading it. Logs go to the home of the user who ran `sudo`.

Rocky Linux 10 only for now; on Ubuntu 24.04 follow the runbook's Ubuntu blocks.

| Order | Script | Runbook | Attended? |
|---|---|---|---|
| 0 | `provision-debug-tools.sh` (`run.sh debug-tools`) | [04](../04-provisioning.md) Phase 1, "Admin tools": tmux, atop recording, htop, nvtop, ... | Short |
| 1 | `provision-phases-2-4.sh` | [04](../04-provisioning.md) Phases 2 to 4: updates, inventory, NVIDIA driver, kernel parameters | Yes: may stop for a reboot (new kernel); Secure Boot must be off ([03](../03-bring-up.md)) |
| 2 | reboot | | |
| 3 | `provision-phase-5.sh` | [04](../04-provisioning.md) Phase 5: Docker, NVIDIA Container Toolkit | Short |
| 4 | `provision-phase-6-fan2go-build.sh` | [04](../04-provisioning.md) Phase 6: sensors, fan2go built for Rocky, `fan2go detect`, fan RPMs | Short; then the fan unplug test by hand |
| 5 | `provision-phase-6-fan2go-config.sh` | [04](../04-provisioning.md) Phase 6: configuration and service | About 2 minutes (fan measurement) |
| 5b | `provision-aide.sh` (`run.sh aide`) | [04](../04-provisioning.md) Phase 7: AIDE (system paths only), nightly check, 3 years of reports | A few minutes (baseline) |
| 6 | `host-checks.sh` | [05](../05-acceptance.md) section 2 | Short: PASS/FAIL list |
| 7 | `accept-gpu-thermal.sh` | [05](../05-acceptance.md) GPU thermal, 10 minutes | Watch it |
| 8 | `accept-short.sh` | [05](../05-acceptance.md) disk health and a short run of every long test | About 3 minutes |
| 9 | `accept-long.sh` | [05](../05-acceptance.md) memory, disks, GPU stability | No: hours, unattended |

Hands-on tests (power loss, BMC power cycle, network failover) have no script: they
need a person at the machine.
