# SSH hang caused by PCIe AER error flood on a Blackwell GPU

Date: 2026-02-11
Hardware: NVIDIA RTX PRO 6000 Blackwell Workstation Edition (96 GB) on an Intel desktop platform (Alder Lake-S PCIe root port)

**Summary.** The server stopped answering SSH and needed a power-button restart. The cause was a continuous flood of PCIe correctable errors (Physical Layer, RxErr) on the link between the CPU root port and the GPU. The errors started at boot and ran for two days at several per second, until I/O stalled and the machine soft-hung. Booting with `pci=noaer` suppresses the error handling overhead. Reseating the GPU and checking the slot link speed are the hardware checks.

## Symptoms

- SSH connections hang: no response, no rejection. The kernel is still alive.
- The kernel log shows several errors per second, starting right after boot:

```
pcieport 0000:00:01.0: AER: Correctable error message received from 0000:00:01.0
pcieport 0000:00:01.0: PCIe Bus Error: severity=Correctable, type=Physical Layer, (Receiver ID)
pcieport 0000:00:01.0:   device [8086:a70d] error status/mask=00000001/00002000
pcieport 0000:00:01.0:    [ 0] RxErr                  (First)
```

- After the reboot the errors continued, and the GPU itself logged a Data Link Layer timeout:

```
nvidia 0000:01:00.0: PCIe Bus Error: severity=Correctable, type=Data Link Layer, (Transmitter ID)
nvidia 0000:01:00.0:   device [10de:2bb1] error status/mask=00001000/0000e000
nvidia 0000:01:00.0:    [12] Timeout
```

- The GPU still works: `nvidia-smi` shows it normal and a model can be loaded.

## Root cause

- Severity "Correctable" means the hardware retries and recovers each failed transfer, but each one costs time.
- Type "Physical Layer" / RxErr means the root port received corrupted data from the link.
- At this rate the kernel AER (Advanced Error Reporting) handler is overwhelmed. I/O latency grows until I/O, including the network stack, blocks. The result is a soft hang, not a crash.
- The errors appear from boot and persist across reboots. Similar reports exist for RTX 5090 and RTX PRO 6000 on many different systems, so a GPU firmware/driver issue is more likely than a local defect. Loose seating, a bad slot, power delivery and board incompatibility were not ruled out.

## Fix

Software:

| Option | Kernel command line | Effect |
|--------|---------------------|--------|
| Disable AER reporting | `pci=noaer` | Suppresses the messages and the AER handler overhead. Does not fix the link. |
| Disable ASPM | `pcie_aspm=off` | Disables PCIe Active State Power Management. Mentioned in forums as a workaround. |
| Disable DRM KMS | `nvidia-drm.modeset=0` | Less unneeded GPU communication on a headless machine. |
| Disable MSI | `pci=nomsi` | Not recommended. Reported to cause high CPU usage. |

Community results for these parameters are mixed.

Hardware and firmware:

1. Reseat the GPU: power down, remove it, clean the contacts, reinstall it firmly.
2. Check that the 12VHPWR / PCIe power connectors are fully seated.
3. Check the slot link speed and width (see below). Some users report that forcing Gen 4 instead of Gen 5 in the BIOS helps.
4. Try another x16 slot if one is available. Inspect slot pins and the GPU connector.
5. Update the motherboard BIOS.

## Verify

```bash
# Watch for new AER messages
journalctl -kf | grep -i "pcie\|aer"
sudo dmesg | grep -i aer

# Negotiated link speed/width vs. capability of the GPU
sudo lspci -vv -s 01:00.0 | grep -E "LnkCap|LnkSta"

# Kernel command line in use
cat /proc/cmdline
```

To let the machine recover by itself from a kernel panic, set in `/etc/sysctl.d/99-watchdog.conf`:

```
kernel.panic = 10
kernel.panic_on_oops = 1
```

For remote machines, out-of-band management (IPMI/BMC) avoids a site visit for a power cycle.

## Related known Blackwell issues

### Virtualization reset bug

RTX 5090 and RTX PRO 6000 can hang the host after a PCIe function-level reset (FLR), for example when a VM with GPU passthrough (KVM/VFIO) shuts down. Only a full power cycle recovers the GPU. NVIDIA can reproduce it. CloudRift offered a $1,000 bounty for a fix ([Tom's Hardware](https://www.tomshardware.com/pc-components/gpus/rtx-5090-pro-6000-bug-forces-host-reboot)).

### PCIe Resource Allocation Issues

A 96 GB card needs a BAR (memory window) far above the 4 GB address range. Some motherboards cannot allocate it. Then the machine hangs at POST with PCIe resource allocation errors, or it boots and the GPU is missing. Enable **Above 4G Decoding** and **Resizable BAR** in the BIOS. A reported workaround on boards that still hang is to boot from the iGPU and force the PCIe slot speed (Gen 5).

### Correctable errors in passthrough

[Proxmox users report](https://forum.proxmox.com/threads/rtx-pro-6000-pcie-bus-error.169862/) `NonFatalErr` and `HeaderOF` (header overflow) errors with the RTX PRO 6000, and "Code 43" in Windows guests. No resolution was found.

## References

- [Tom's Hardware: RTX 5090/PRO 6000 reset bug](https://www.tomshardware.com/pc-components/gpus/rtx-5090-pro-6000-bug-forces-host-reboot)
- [VideoCardz: virtualization reset issue](https://videocardz.com/newz/nvidia-rtx-5090-and-rtx-pro-6000-reportedly-hit-by-virtualization-reset-issue-1000-bounty-offered)
- [Proxmox Forum: RTX Pro 6000 PCIe bus error](https://forum.proxmox.com/threads/rtx-pro-6000-pcie-bus-error.169862/)
- [NVIDIA Developer Forums: RTX 4090 AER errors](https://forums.developer.nvidia.com/t/kernel-pcieport-000001-0-aer-device-recovery-failed-with-rtx-4090-only/231274)
- [Arch Linux Forums: PCIe Physical Layer errors](https://bbs.archlinux.org/viewtopic.php?id=242182)
- [Proxmox Forum: AER correctable error solutions](https://forum.proxmox.com/threads/aer-correctable-error-message-received.156497/)
