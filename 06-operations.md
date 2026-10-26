# 06 Operations: day 2

What happens to a running S2 after the handoff: planned driver and kernel changes, and
what to do when a GPU or an NVMe disk fails. The BMC recovery steps (KVM stuck, card restart) are in
[03 Bring-up](03-bring-up.md).

## Planned driver or kernel change

1. Stop the models on the machine from the control plane, or on the machine:
   `onprem-ai-node stop`.
2. Release the holds.
   - **Ubuntu 24.04:** `apt-mark unhold` the kernel packages; for a new driver branch
     or version, install its pinning package (`apt-get install --purge
     nvidia-driver-pinning-<branch or version>`).
   - **Rocky Linux 10:** `dnf versionlock delete` the kernel packages (and the Docker
     packages when Docker changes too); for a new driver branch, change the branch in
     the NVIDIA lines of `/etc/dnf/plugins/versionlock.list`.
3. Upgrade (`apt-get update && apt-get -y full-upgrade`, or `dnf upgrade --refresh`),
   then `dkms status`: the NVIDIA module is installed for the kernel that boots next.
4. Reboot. A running kernel module is never replaced in place.
5. The host checks of [05 Acceptance](05-acceptance.md), then hold the kernel again (`apt-mark hold`, or
   `dnf versionlock add` as in [provisioning](04-provisioning.md) Phase 3).
6. `onprem-ai-node start`.

Change one machine first and keep it serving for a day before the rest.

## When a GPU fails

The control plane raises GPU alerts with their recovery steps; the full Xid reference
is the product documentation's **GPU Alert Reference**. In short:

| Symptom | First step |
|---|---|
| `driver/library version mismatch` | A driver upgrade happened without a reboot: reboot ([260521](learnings/260521-nvidia-driver-version-mismatch.md)) |
| `gpu requires reset` | `nvidia-smi --gpu-reset -i <index>` with nothing on the GPU, else reboot ([260524](learnings/260524-gpu-requires-reset-nvml-error.md)) |
| `GpuThermalRampRateHigh`, or a passive GPU above 80 C | `systemctl status fan2go`, `journalctl -u fan2go`; read the GPU fans' RPM in `sensors` (`fan4` and `fan6`). A fan at 0 RPM with PWM above 0 is a dead fan or a loose cable. The two GPU fans sit in series, so the other one keeps running, but with far less pressure: replace the fan the same day, then delete `/var/lib/fan2go/fan2go.db` and restart fan2go so it measures the new fan ([provisioning](04-provisioning.md) Phase 6) |
| Xid 79, GPU fell off the bus | Reboot. A Blackwell GSP timeout can need a full power cycle through the BMC, not a reboot ([260526](learnings/260526-gpu-pcie-drop-recovery.md)) |
| SSH hangs, `AER: Correctable` floods the kernel log | Add `pci=noaer` ([provisioning](04-provisioning.md) Phase 4), reseat the GPU, check the slot speed ([260211](learnings/260211-ssh-hang-pcie-gpu-errors.md)) |
| Tensor-parallel model hangs at NCCL start | `iommu=pt` missing; check `dmesg` for `IO_PAGE_FAULT` ([260718](learnings/260718-amd-vi-iommu-nccl-p2p-hang.md)) |

## When an NVMe disk fails

Sign: `/proc/mdstat` shows `[U_]` or `[_U]` instead of `[UU]`, or `mdmonitor` reports
a failed member. The two NVMe disks are one RAID 1 mirror
([04](04-provisioning.md) Phase 1): the machine keeps running on the other disk.
Replace the failed one on a planned visit, soon: a second failure loses everything.

1. Find the failed disk: `mdadm --detail /dev/md/*` names it; note its serial
   (`smartctl -i /dev/nvmeN`) and match it with the [machine record](machine-record.md),
   which says which slot holds which serial.
2. Stop the models, shut down, unplug. The disks sit under the GPUs: take out the GPU
   above the slot first ([02](02-assembly.md)).
3. Put in a disk of the same model and at least the same size, in the same slot
   (never M.2_2).
4. Boot (from the remaining disk), then copy the partition table to the new disk and
   add its partitions back to each array:

   ```sh
   sfdisk -d /dev/nvme<good> | sfdisk /dev/nvme<new>       # same partitions on the new disk
   mdadm --manage /dev/md/<name> --add /dev/nvme<new>p<N>   # once per array
   cat /proc/mdstat                                         # resync runs; [UU] when done
   ```

   Ubuntu 24.04 with one ESP per disk: format the new ESP and reinstall the boot
   loader on it (`dpkg-reconfigure grub-efi-amd64`). Rocky Linux 10's ESP is itself a
   mirror and resyncs with the rest.
5. Record the new serial in the machine record.
