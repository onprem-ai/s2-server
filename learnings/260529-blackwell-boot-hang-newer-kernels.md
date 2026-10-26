# Blackwell Boot Hang on Newer Kernels (nouveau and AER Changes)

**Date:** 2026-05-29

## Summary

- **What happened:** A live USB boot froze on machines with a Blackwell GPU
  at this line:
  `nouveau 0000:01:00.0: gsp: RM version: 570.144`
- **Cause:** Ubuntu's 24.04 HWE kernel moved from **6.14** to **6.17**. That
  kernel brought two separate problems on Blackwell GPUs:
  1. nouveau tries to start the GSP firmware on Blackwell and hangs. nouveau
     does not support Blackwell.
  2. Changed PCIe AER handling floods the kernel with errors while the GPU
     is enumerated.
- **Fix:** Keep nouveau off the GPU (`nomodeset`, or blacklist nouveau and
  use the NVIDIA driver) and add `pci=noaer`.

## Details

1. **nouveau GSP hang.** nouveau detects the GPU and tries to load the
   NVIDIA GSP firmware. GSP init freezes the boot. `nomodeset` stops nouveau
   from loading at all.
2. **PCIe AER floods.** With 6.17 the kernel floods on PCIe errors during
   GPU enumeration. `pci=noaer` suppresses these. Note that `pci=noaer` also
   hides AER errors that can announce an Xid 79; see
   [260526-gpu-pcie-drop-recovery.md](260526-gpu-pcie-drop-recovery.md).

A system that runs the NVIDIA driver (with `nvidia-drm.modeset=0`) and
already has `pci=noaer` was not affected: nouveau never loads there. The
hang hit a text-only live system that booted its own kernel with its own
GRUB config, which had neither parameter.

## Fix

For a text-only system (no GPU driver needed), add both parameters to every
GRUB menu entry:

```
linux /boot/vmlinuz ... nomodeset pci=noaer
```

For a system that uses the GPU, do not rely on nouveau. Blacklist it and
use the NVIDIA driver:

```bash
echo -e "blacklist nouveau\noptions nouveau modeset=0" | \
  sudo tee /etc/modprobe.d/blacklist-nouveau.conf
sudo update-initramfs -u
```

Verify after boot:

```bash
cat /proc/cmdline
lsmod | grep nouveau      # should print nothing
```

## Lessons

- An HWE kernel update can change GPU and PCIe behavior. Pin the kernel
  deliberately and test a new kernel before you roll it out.
- If several systems boot different kernels or GRUB configs (for example a
  live USB and the installed system), apply kernel command line workarounds
  in **every** config. Changes to one do not carry over to the other.
