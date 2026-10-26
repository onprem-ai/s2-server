# Option: RAID 0 for compute-only nodes

Optional. The default is the RAID 1 mirror of
[04 Provisioning](../04-provisioning.md#phase-1-install-the-operating-system), Phase 1.
This page lists only what differs from it.

## When to use it

A compute-only node: it keeps no data that exists only on this machine. Model weights
and model images can be downloaded again; nothing else on the node needs to survive.
RAID 0 gives the space of both disks (2x 1 TB = 1.8 TB usable instead of 930 GB) for
the same disks, so more models fit on the machine, or smaller disks do.

The cost: **one failed disk loses the whole machine**, system and models. It is
reinstalled on new disks, then the platform downloads its models again. Choose RAID 0
only when that reinstall is acceptable.

## Layout

In the installer's custom partitioning:

| Partition | Size | Where | Holds |
|---|---|---|---|
| EFI system partition | 1 GB | First NVMe disk only | `/boot/efi` |
| `/boot` | 2 GB | First NVMe disk only | Kernels, initramfs |
| Rest | All the rest | RAID 0 over both disks | LVM, `/` (XFS or ext4) |

- `/boot/efi` and `/boot` sit on the first disk only. Mirroring them would not help:
  with RAID 0 the system needs both disks anyway. The firmware cannot read a RAID 0
  EFI partition.
- Rocky Linux 10: on each of the three mount points, choose the device type and
  "RAID Level"; only the large one gets "RAID0" over both disks.
- Swap as in Phase 1: keep the installer's swap volume, on the RAID 0.
- The second disk keeps a few GB unused at its end: RAID 0 uses equal-sized members,
  and the first disk also holds `/boot` and `/boot/efi`. Normal.

## Checks after the first boot

Instead of the RAID 1 checks of Phase 1:

```sh
cat /proc/mdstat        # one array, "active raid0", both NVMe partitions in it
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS
swapon --show           # the installer's swap volume
```

`/proc/mdstat` has no `[UU]` for RAID 0: there is no redundancy to show. A RAID 0 with
a failed disk does not run degraded; the file system fails.

## What changes later

- **[05 Acceptance](../05-acceptance.md):** the "mirror fully synced" condition does not
  apply; the `smartctl` check of both disks does, and matters more.
- **[06 Operations](../06-operations.md), "When an NVMe disk fails":** does not apply.
  A failed disk means: replace it, reinstall from Phase 1, install the platform again.
  Watch the disks' health (`smartctl -a /dev/nvme0`, `/dev/nvme1`: media errors,
  percentage used) so a disk is replaced before it fails.
- **[Machine record](../machine-record.md):** note "RAID 0, compute-only", so nobody
  stores data on it that cannot be lost.
