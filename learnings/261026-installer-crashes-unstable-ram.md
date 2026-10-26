# OS Installers Crash at Random Places: Unstable RAM (EXPO) on the ProArt X870E

> **Issue:** On new ProArt X870E-CREATOR WIFI machines, Ubuntu 24.04 and Rocky Linux
> 10.2 installers failed again and again, each time somewhere else. The same USB sticks
> installed fine on another machine.
>
> **Two causes, easy to mix up:** unstable RAM made programs crash anywhere; separately,
> old LVM volumes left on the disks made the installers' disk scan crash.
>
> **Cause:** RAM not stable at its settings (EXPO on, DDR5 on AM5). Programs crash at
> random because the memory flips bits; it looks like an installer bug but is hardware.
>
> **Fix:** EXPO Disabled in the BIOS (first page) and, on an old BIOS, an update to the
> latest release ([02 Assembly](../02-assembly.md#first-power-on), steps 3 and 5;
> [03 Bring-up](../03-bring-up.md#6-firmware-updates)). Then a memory test.

**Date:** 2026-10-25 / 2026-10-26
**Hardware:** ASUS ProArt X870E-CREATOR WIFI, Ryzen 9000 (24 threads), DDR5

## How to recognise it

Two or more installers or live systems that work elsewhere, failing on the new machine
at different places on each attempt. One crash alone could be a software bug; crashes
in unrelated programs, at different steps, are memory.

## What was seen

### Unstable RAM (BIOS 2103, Ubuntu 24.04 installer, kernel 6.8.0-139)

- Kernel `BUG: Bad page state`: `bad_page` / `free_page_is_bad_report` in the call
  trace, while `localedef` exited after a `general protection` fault.
- `Tainted: G B D`: B = a bad page was already reported, D = the kernel had already
  oopsed. Not the first error of that boot.
- `RDI: 800058fca07deac0`: a normal user-space address (`0x000058fca07deac0`) with the
  top bit flipped. A single flipped bit is the classic sign of RAM errors.

EXPO Disabled fixed it.

### Unstable RAM on an old BIOS (BIOS 1805)

- `init[1]: segfault at ... error 4 in ld-linux-x86-64.so.2`, 2.8 s into boot: the
  first program started crashed in the dynamic loader, before any installer ran.

Fixed by the BIOS update to the latest release (2503) with EXPO Disabled: after it, the
kernel log showed no segfaults or memory errors.

### Old LVM volumes on the disks (not the RAM)

The same machine, after the BIOS fix, still failed in both installers, at the disk
step:

- Rocky 10.2 Anaconda: "unknown error" right after the language screen, traceback in
  `dasbus/client/handler.py` line 509 `_handle_method_error`; the traceback file
  (`/tmp/anaconda-tb-*`, shell on tty2) names the real error:
  `The object with LVM ID 'vg-system/...' doesn't exist`.
- Ubuntu installer: "Sorry, there was a problem completing the installation" during
  `curtin block-meta simple` / "removing previous storage devices".

Cause: both disks came from an earlier installation and each held a volume group with
the same name. LVM warns `VG name vg-system is used by VGs ... Fix duplicate VG names`,
and the installers' disk scan crashes on it. Fix: from the installer's shell, deactivate
and wipe the old layout, then restart the installer:

```sh
vgchange -an
wipefs -a /dev/nvme0n1p* /dev/nvme1n1p*    # every partition of both disks
wipefs -a /dev/nvme0n1 /dev/nvme1n1
```

This erases everything on both disks.

A Python traceback in the installer is not by itself a sign of bad RAM: read the
traceback file first. A crash in a different program on every attempt is.

## What to do, in order

1. BIOS: EXPO Disabled (JEDEC default), load defaults (F5) if anything else was
   changed (PBO, Curve Optimizer, undervolt).
2. BIOS update to the latest release (old releases have weaker DDR5 training), then
   EXPO Disabled again: the update resets the settings.
3. Memory test: MemTest86, or Memtest86+ v7 or newer (older versions do not support
   DDR5/AM5). At least one full pass, zero errors.
4. Errors anyway: reseat the RAM, test each module alone in the slot the board manual
   names, swap in a module from a working machine.
5. RAM clean and still crashing: the CPU next (swap with another board).

## Not the cause

- The installer USB sticks or ISOs: the same sticks worked on another machine, and a
  bad image does not cause kernel bad-page reports.
- The OS: two distributions failed the same way.
- The amount of RAM: the kernel reported about 16 GB less than installed at first;
  check `Memory: ...K available` in the boot log against the modules when in doubt.
- The ACPI, PCI and DMI lines in the boot log: normal output, no fault.
