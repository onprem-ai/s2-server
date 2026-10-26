# GPU PCIe Drop — Xid 79 Root Cause Analysis and Recovery

**Date:** 2026-05-26
**GPU:** NVIDIA RTX PRO 6000 Blackwell
**Kernel:** 6.17.0-23-generic
**Driver:** 595.71.05 (open kernel module)

## Summary

- **What happened:** During LLM inference the GPU dropped off the PCIe bus
  (`Xid 79: GPU has fallen off the bus`). A driver reload and a PCIe rescan
  did not bring it back. A reboot did.
- **Cause:** Most likely PCIe link power management (ASPM). The link
  retrains between Gen1 at idle and Gen5 under load. A Surprise Link Down
  during that retrain makes the GPU unreachable.
- **Fix:** Disable PCIe link power management with the kernel parameters
  `pcie_aspm=off pcie_port_pm=off`.

## What We Saw

The drop was instant. There was no warning before it.

```
Xid 79: GPU has fallen off the bus
Xid 154: GPU recovery action → Node Reboot Required
rpcSendMessage failed        (hundreds of times — GSP unresponsive)
```

- `nvidia-smi` exits with code 6:
  `Unable to determine the device handle for GPU0: Unknown Error`.
- GPU containers fail with
  `nvidia-container-cli.real: detection error: nvml error: unknown error`.
- `lspci` still lists the GPU, but the driver cannot talk to it.
- Driver reload fails with `NVRM: No NVIDIA GPU found`.
- No PCIe AER errors were logged, because AER was disabled with `pci=noaer`.
- No thermal or power events. The GPU was cool (32°C) after reboot.

## Root Cause Analysis

### Primary suspect: PCIe ASPM during the Gen1↔Gen5 link retrain

ASPM was at the "default" policy, so it was not disabled. Blackwell GPUs
have a known issue: ASPM can cause a Surprise Link Down while the link
changes speed between Gen1 (idle) and Gen5 (load). The root port suspends
during the retrain, and the GPU becomes unreachable. The usual fix is
`pcie_aspm=off pcie_port_pm=off`.

### `pci=noaer` masks diagnostics

AER (Advanced Error Reporting) logs PCIe errors. In Ubuntu bug 2152037 the
crash sequence was: PCIe correctable RxErr → Xid 79 → Xid 154. The AER
errors announce the Xid 79. With `pci=noaer` these errors are hidden, so
you cannot see whether correctable errors came before the crash.

### Not the cause: ACPI BIOS errors

Errors like `ACPI BIOS Error: ... _DSM ... AE_ALREADY_EXISTS` can appear on
every boot. This is a known cosmetic BIOS bug on many Intel 600/700/800
series boards with NVIDIA GPUs. The ACPI `_DSM` method tries to create a
buffer field that already exists. It does not affect the GPU and is not
related to Xid 79. Only a BIOS update fixes it.

### Not the cause: thermal or power limits

No HW Thermal Slowdown or HW Power Brake events were logged before the
crash.

## Causes of Xid 79 / "Fallen Off the Bus"

Collected from NVIDIA forums, GitHub issues, kernel bug reports and
hardware guides. Roughly ordered from most to least likely.

1. **PCIe link power management (ASPM).** See above. Fix:
   `pcie_aspm=off pcie_port_pm=off`.
2. **Kernel regression.** Some kernel versions break PCIe error handling.
   Ubuntu bug 2152037: Ubuntu kernel 6.8.0-111 (a 6.8 point release) causes
   Xid 79 on RTX PRO 5000 Blackwell under load; 6.8.0-110 is fine, with the
   same driver, hardware and workload. Forum reports also show Xid 79 on
   kernels 6.14 and 6.17. If crashes continue after the ASPM fix, test an
   older kernel.
3. **PSU Power Delivery / transient spikes.** See the section below.
4. **GPU VBIOS / firmware bug.** Early RTX PRO 6000 Blackwell units with
   VBIOS 98.02.52.00.2 can fault under sustained compute load. Registers
   return poison values (`0xbadf3200`). Recovery needs a full power cycle,
   not just a reboot. The bug persists across drivers 580.x and 595.x.
   Power-limiting to 500 W prevented it for one user. Check the version
   with `nvidia-smi --query-gpu=vbios_version --format=csv` and contact
   NVIDIA if it is the early one.
5. **PCIe Gen5 signal integrity.** Gen5 (32 GT/s) is marginal on many
   consumer and workstation boards. Some Blackwell builds became stable only
   at PCIe Gen4 (forced in the BIOS). This halves peak bandwidth. On some
   boards the open kernel module falls back to Gen1 instead of Gen4 when
   Gen5 fails.
6. **GSP firmware hang (Blackwell).** Blackwell uses GSP firmware for
   driver communication. Under sustained inference the GSP can stop
   answering RPC calls. This shows as Xid 119 (GSP timeout), Xid 79, or a
   silent hang with no Xid. A Blackwell GSP timeout can need a full power
   cycle (cut power completely, for example through the BMC), not just a
   reboot. The GSP cannot be disabled with the open kernel module.
   Workaround: power-limit the GPU (`nvidia-smi -pl <watts>`); users report
   320 W or 500 W on a 600 W card.
7. **Physical seating or connectors.** A loose card or power connector.
   Reseat the card and power cables. Moving the GPU to another slot fixed
   Xid 79 for one user.
8. **Overheating.** Rare. The GPU usually throttles first.
9. **IOMMU / DMA settings.** Some users report that `iommu=pt` or
   `iommu=soft idle=nomwait` helped.
10. **Resizable BAR / MMIO conflicts.** Mostly a multi-GPU problem: each
    Blackwell GPU requests 128 GB of MMIO space. Check with
    `cat /proc/driver/nvidia/params | grep EnableResizableBar`.
11. **Outdated system BIOS.** BIOS updates can fix PCIe retimers and power
    management. Dell KB000230721: a retimer firmware update fixed Xid 79.
12. **Driver bugs.** Blackwell needs the open kernel modules. Watch the
    NVIDIA release notes.

## PSU Power Delivery / Transient Spikes

A 600 W GPU can draw short spikes of 128–157% of its TDP (770–940 W)
during LLM inference. On a **multi-rail PSU**, such a current spike can trip
one rail's over-current protection (OCP). The PSU shuts down and latches
off. The machine goes dark with no log entry: no kernel panic, no Xid,
nothing. The power button may not respond, because standby power is gone.
Only a mains power cycle (PSU switch or power cord) brings it back.

- One reported RTX PRO 6000 Blackwell inference crash was fixed by
  switching the PSU from multi-rail to single-rail mode.
- If the system dies with no log entry at all, suspect this first.
- To confirm, put a power meter between outlet and PSU. If it reads 0 W
  after the crash, the PSU has shut off.

## Recovery Procedure

### Step 1: Stop GPU containers and reload the driver

This usually fails for Xid 79, but try it first.

```bash
# Find and stop all containers that use the GPU
docker ps
docker stop <container> [<container> ...]

# Unload and reload the NVIDIA modules
sudo rmmod nvidia_uvm nvidia_drm nvidia_modeset nvidia
sudo modprobe nvidia && nvidia-smi
```

### Step 2: If modprobe fails, remove the device and rescan PCIe

```bash
# Find the GPU address with: lspci | grep -i nvidia
echo 1 | sudo tee /sys/bus/pci/devices/0000:<bus>:00.0/remove
sleep 2
echo 1 | sudo tee /sys/bus/pci/rescan
```

### Step 3: If the rescan fails, reboot

```bash
sudo reboot
```

If the GPU is still missing after a reboot, do a full power cycle (cut
power, for example through the BMC). Then start the GPU containers again.

## Post-Reboot Verification

```bash
# GPU detected and working
nvidia-smi

# PCIe link. Gen1 (2.5 GT/s) at idle is normal; the GPU goes to Gen5 under load.
sudo lspci -vvv -s <bus>:00.0 | grep LnkSta
nvidia-smi -q | grep -A4 'PCIe Generation'

# Replay / remapped / retired counters should be zero
nvidia-smi -q | grep -E 'Replays|Remapped|Retired'

# ACPI _DSM errors are cosmetic, ignore them
sudo dmesg | grep '_DSM'
```

## Fix: Disable PCIe Link Power Management

Add these kernel parameters:

```
pcie_aspm=off pcie_port_pm=off
```

The full GPU parameter set used here was:

```
pcie_aspm=off pcie_port_pm=off pci=noaer nvidia-drm.modeset=0
```

Apply with GRUB:

```bash
sudo nano /etc/default/grub     # add the parameters to GRUB_CMDLINE_LINUX_DEFAULT
sudo update-grub
sudo reboot
cat /proc/cmdline               # verify
```

## Monitoring

```bash
nvidia-smi
nvidia-smi -q | grep 'Replays Since Reset'   # rising = marginal link
nvidia-smi -q | grep 'GPU Current Temp'
nvidia-smi -q | grep 'Power Draw'
nvidia-smi --query-gpu=vbios_version --format=csv
sudo dmesg | grep -iE 'NVRM|Xid|AER|pci.*error'
```

If the crash comes back, escalate in this order:

1. Disable ASPM (done).
2. Force PCIe Gen4 in the BIOS.
3. Power-limit the GPU: `nvidia-smi -pl 500`.
4. Test an older kernel.
5. Check the VBIOS version; contact NVIDIA if it is early firmware.
6. Run `nvidia-bug-report.sh` right after the crash and file an NVIDIA bug.

## References

- [260211-ssh-hang-pcie-gpu-errors.md](260211-ssh-hang-pcie-gpu-errors.md) — earlier PCIe GPU issue
- [Ubuntu bug 2152037](https://bugs.launchpad.net/ubuntu/+bug/2152037) — kernel 6.8.0-111 Xid 79 regression on RTX PRO 5000 Blackwell
- [NVIDIA open-gpu-kernel-modules #1010](https://github.com/NVIDIA/open-gpu-kernel-modules/issues/1010) — Gen1 fallback
- [NVIDIA open-gpu-kernel-modules #1111](https://github.com/NVIDIA/open-gpu-kernel-modules/issues/1111) — GSP firmware halt under sustained inference
- [NVIDIA open-gpu-kernel-modules #942](https://github.com/NVIDIA/open-gpu-kernel-modules/issues/942) — system freeze on 580.82.07
- [NVIDIA open-gpu-kernel-modules #949](https://github.com/NVIDIA/open-gpu-kernel-modules/issues/949) — driver bug with Blackwell
- [NVIDIA open-gpu-kernel-modules #507](https://github.com/NVIDIA/open-gpu-kernel-modules/issues/507) — Xid 79 reports
- [NVIDIA open-gpu-kernel-modules #1132](https://github.com/NVIDIA/open-gpu-kernel-modules/issues/1132) — GPU lock with ReBAR disabled
- Dell KB000230721 — Xid 79 caused by PCIe retimer firmware
- voipmonitor/rtx6kpro (GitHub) — Blackwell PCIe ASPM troubleshooting
- NVIDIA Developer Forums — "RTX PRO 6000 Blackwell (GB202) — Recurring full chip reset during sustained LLM inference"
- checkfix.io — "In-house AI: GPU Crash Caused by Multi-Rail OCP"
- cr0x.net — "Power Supplies for Modern GPUs"
- OXMIQ blog — "Four RTX 6000 Blackwell GPUs in One Machine" (forced Gen4)
