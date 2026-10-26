# 03 Bring-up: BMC, BIOS, firmware

Everything before the operating system: the IPMI card (BMC) set up and locked down, the
firmware display moved to the card so the BIOS is reachable remotely, the BIOS settings,
firmware updates, and Secure Boot off so the DKMS-built NVIDIA driver loads.

Tested with BIOS 2503, card firmware 1.3.13, Rocky Linux 10.2 and 2x RTX PRO 6000.
These settings cannot be fixed from Linux later without a reboot into the firmware; without
a working BMC that means a person at the console.

Board manual and BIOS manual: [`hardware/mainboard/`](hardware/mainboard/); card
manual: [`hardware/ipmi-card/`](hardware/ipmi-card/). KVM tooling for an AI agent:
[asus-ipmi-mcp](https://github.com/onprem-ai/asus-ipmi-mcp).

The commands below use `<bmc address>` for the IPMI card and `<host address>` for the
machine. Per machine, both go in its [machine record](machine-record.md). Passwords are
never stored in this repository.

## 1. BMC and IPMI card

Set up the BMC first, before the operating system: every later step can then be
done, and recovered, from the BMC's remote console. The card is wired at assembly
([02](02-assembly.md)).

On the S2 the BMC is the ASUS IPMI Expansion Card-SI (ASPEED AST2600), with its own
LAN port, a web console (HTML5 remote console, virtual media) and IPMI 2.0 over LAN
(card manual and key facts in [`hardware/ipmi-card/`](hardware/ipmi-card/)).

The card ships with two administrator accounts, `admin` (default password `admin`) and
`Administrator` (default password `superuser`). The first login forces a new password
for `admin` only; `Administrator` keeps its default until it is changed by hand.
Anyone on the management network who knows the defaults has the machine's power,
console and boot media. Both passwords are changed in the IPMI and power test of
[02](02-assembly.md) (step 9), before the BMC's LAN port is connected to any shared
network.

TODO, to be completed on the first S2 machine:

- [ ] Wiring checked ([02](02-assembly.md), "IPMI card"); the card's own LAN port on the
      management network.
- [ ] Network: static IP address or DHCP reservation for the BMC, outside the DHCP
      server's automatic range; record it with the machine.
- [ ] IPv6 off on the card (web console, Settings, network settings). The card is
      managed over IPv4 only; with IPv6 on, it can take an IPv6 address by itself that
      nobody watches or filters.
- [ ] Both accounts have new passwords ([02](02-assembly.md), step 9): log in as
      `admin` and as `Administrator` with the new ones, and check that `admin` / `admin`
      and `Administrator` / `superuser` are refused. Record where the passwords are
      kept (password manager entry name, never in this repository).
- [ ] Decide whether `admin` stays enabled or is disabled once `Administrator` has a
      new password.
- [ ] Turn off what is not used: unused services, IPMI over LAN cipher suite 0 and
      anonymous login, if the firmware offers them.
- [ ] Update the BMC firmware to the vendor's current release.
- [ ] Check from another machine: the web console opens, the remote console shows the
      screen, `ipmitool -I lanplus -H <bmc address> -U Administrator -P <password>
      chassis status` answers, and the default passwords are refused.
- [ ] Serial over LAN: check that the kernel console (`console=ttyS0,115200n8`,
      [04](04-provisioning.md) Phase 4) reaches the BMC.
- [ ] Power cycle through the BMC (`chassis power cycle`): the step a Blackwell GSP
      fault needs ([06](06-operations.md)).
- [ ] Both card passwords stored in the password manager. On the public BIOS the host
      cannot reach the card, so a lost card password cannot be reset from the host
      ([`hardware/ipmi-card/`](hardware/ipmi-card/README.md#lost-password)).
- [ ] Open: in-band access from the host (`ipmitool` on the host, password reset,
      board sensors) needs the special IPMI BIOS from ASUS support
      ([`hardware/ipmi-card/`](hardware/ipmi-card/README.md#access-from-the-host-in-band-needs-the-special-ipmi-bios)).
      Decide whether to request it: it cannot be rolled back. Without it the card still
      does what the S2 needs most: power control, remote screen, keyboard and mouse,
      virtual media.

## Why the firmware display must move to the card

- **The firmware only draws on the primary display.** Out of the box that is the CPU's onboard
  Radeon (board HDMI/DP), so POST, BIOS setup, shim and MokManager are **invisible** through the
  IPMI card. Linux later switches to the card's ASPEED chip, which is why the desktop was always
  visible but the BIOS never was. Check with:
  `for c in /sys/class/drm/card*; do echo "$c $(cat $c/device/boot_vga 2>/dev/null)"; done`
  → `boot_vga=1` marks the firmware's display (here `0000:7c:00.0` Radeon vs `0000:0b:00.0` ASPEED).
- **The card's UEFI video driver (GOP) is not accepted by this BIOS:**
  "The VGA card is not supported by UEFI driver". The firmware then enables **CSM** itself and drives
  the card in legacy mode. CSM and Secure Boot cannot both be on.
- **Secure Boot blocks the NVIDIA driver** built by DKMS (`Loading of module with unavailable key is
  rejected`). Enrolling the DKMS key (MOK) needs the blue MokManager screen at boot, which is only
  visible if the firmware display goes through the card, and that only works with CSM, i.e. without
  Secure Boot. Therefore: **Secure Boot off** is the practical route on this board.

The two RTX PRO 6000 Server Edition cards are "3D controllers" without display outputs; they are
never chosen as the firmware display.

## 2. Make the IPMI card the firmware display (once, needs a monitor)

At the machine, monitor on the board's HDMI, keyboard attached:

1. Reboot, press **Del** → BIOS → **F7** (Advanced Mode).
2. **Advanced → NB Configuration → Primary Video Device: `PCIE Video`** (not `IGFX` – that is the onboard graphics).
3. In the same menu: **Integrated/Onboard Graphics: `Disabled`**.
4. **F10**, Ok. The board monitor stays dark from now on – expected.

From here everything is remote. Fallback if nothing shows anywhere: Clear CMOS (rear I/O button,
PSU off) brings the onboard graphics back.

## 3. Open the remote console

In a browser: `https://<bmc address>`, log in, then **Remote Control → Launch H5Viewer**.
For an AI agent: the MCP tools `screenshot`, `click`, `press_keys` from
[asus-ipmi-mcp](https://github.com/onprem-ai/asus-ipmi-mcp).

The card allows one controlling remote console session: close other viewers first. A
black screen with "No Signal" while the host is on usually means the host's display is
asleep: one mouse move wakes it. If the console gets no picture at all, the card's KVM
is stuck: restart the card (the host keeps running):

```bash
curl -sk -u "admin:$BMC_PASS" -X POST -H 'content-type: application/json' \
  https://<bmc address>/redfish/v1/Managers/Self/Actions/Manager.Reset -d '{"ResetType":"ForceRestart"}'
# back after ~60-90 s; give the KVM service another ~60 s
```

## 4. Reboot into the BIOS

From the host shell (SSH) or via the card:

```bash
ssh ops@<host address> 'sudo systemctl reboot'
```

On the first boot after section 2 the AMI POST screen (800×600) says *"The VGA card is not supported by
UEFI driver … CSM settings have been changed … press F1 to enter BIOS setup, F2 to continue"*.
Press **F1**. On later boots press **Del** repeatedly during POST (about every half
second from the moment of the reboot until the BIOS appears).

## 5. BIOS settings

### Rules for any GPU machine

Do these in the firmware setup or through the BMC. They cannot be fixed from Linux
later without a reboot into the firmware, and on a machine without a BMC that means
a person at the console.

| Setting | Value | Why |
|---|---|---|
| Boot mode | UEFI, CSM off (S2 exception: CSM on, see below) | Large-BAR GPUs need it |
| Above 4G Decoding | Enabled | A 96 GB card needs a BAR window far above 4 GB; without it the machine hangs at POST or the GPU is missing ([260211](learnings/260211-ssh-hang-pcie-gpu-errors.md), "PCIe Resource Allocation Issues") |
| Resizable BAR | Enabled | Same reason |
| Secure Boot | Disabled, or plan the MOK enrollment ([04](04-provisioning.md) Phase 3) | The NVIDIA kernel module is built by DKMS on the machine and must be signed with a key the firmware trusts; the enrollment needs the console at the next boot |
| SR-IOV | Disabled unless used | Fewer PCIe resources to allocate |
| PCIe ACS | Disabled for multi-GPU machines without PCIe switches in use by VMs | ACS forces peer-to-peer traffic through the root complex; NCCL's bare-metal guidance is to disable it ([NCCL troubleshooting](https://docs.nvidia.com/deeplearning/nccl/user-guide/docs/troubleshooting/gpu_troubleshooting.html)) |
| PCIe slot speed | Auto; force Gen4 only after Gen5 instability is shown | Some Blackwell builds became stable only at Gen4 ([260526](learnings/260526-gpu-pcie-drop-recovery.md)) |
| Restore on AC power loss | Power on | The inference node comes back by itself after an outage |
| BMC / IPMI | Configured, reachable, password changed (section 1) | The only way back in after a hang or a lost SSH key; a machine without one needs a person at the console |

### S2 values

| Setting | Value |
|---|---|
| Above 4G Decoding, Resizable BAR | Enabled |
| PCIe bifurcation of PCIEX16(G5)_1 | Auto (x8/x8 with both GPUs) |
| Memory | **EXPO Disabled** (JEDEC default), set at the first power-on ([02](02-assembly.md#first-power-on)); EXPO only after a memory test (MemTest86 or Memtest86+ v7 or newer) passes |
| Wi-Fi, Bluetooth | Disabled |
| Fan headers of the GPU fans | Any mode; fan2go takes them over |
| Restore AC power loss | Power on |
| Server Mgmt / IPMI menu | Not in the public BIOS: the card's in-band access from the host needs a special BIOS from ASUS support ([`hardware/ipmi-card/`](hardware/ipmi-card/README.md#access-from-the-host-in-band-needs-the-special-ipmi-bios)) |

PCIe ACS has no setting on this board.

On the S2, CSM stays on: the IPMI card's video only works through CSM (section 2), and
with CSM on, Secure Boot is off. CSM can hide Resizable BAR on ASUS boards: after the
change, check that both GPUs still get their large BAR (`Region 1` in the inventory of
[04](04-provisioning.md) Phase 1, both GPUs in `nvidia-smi` with their full memory).

### Boot and Secure Boot through the KVM (F7 for Advanced Mode)

| Where | Setting | Value | Why |
|---|---|---|---|
| Boot → CSM | Launch CSM | **Enabled** (firmware sets it) | needed for the card's video |
| Boot → CSM | Boot Device Control | UEFI and Legacy OPROM | leave |
| Boot → CSM | Boot from Network Devices | **UEFI only** | was Legacy only |
| Boot → CSM | Boot from Storage Devices | **UEFI only** | Rocky is a UEFI install; Legacy only would not boot it |
| Boot → CSM | Boot from PCI-E/PCI Expansion Devices | **Legacy only** – leave | the card's video ROM is legacy |
| Boot → Secure Boot | OS Type | **Other OS** | this is "Secure Boot off" on ASUS |

Through the remote console: **Esc** goes back from a submenu. **F9** searches the BIOS
settings by name. Take a screenshot after each click; positions shift between menus.

**F10** → the dialog lists exactly the changes:
`Boot from Network Devices [Legacy only]->[UEFI only]`, `Boot from Storage Devices [Legacy only]->[UEFI only]`,
`OS Type [Windows UEFI mode]->[Other OS]` → **Ok**. The host boots Linux (~45 s to SSH).

## 6. Firmware updates

### BIOS

Always the latest release for the ProArt X870E-CREATOR WIFI. Not through the IPMI card:
ASUS lists remote BIOS update as unsupported on this board
([compatibility list](hardware/ipmi-card/README.md#what-the-card-can-do-on-the-s2s-board)).
The current version is on the first BIOS page, or from Linux:
`sudo dmidecode -s bios-version`.

**Download.** The board's
[ASUS support page, BIOS & Firmware](https://www.asus.com/motherboards-components/motherboards/proart/proart-x870e-creator-wifi/helpdesk_bios/?model2Name=ProArt-X870E-CREATOR-WIFI):
the top entry under **BIOS** is the latest. Take a release without "Beta Version".
The page lists a SHA-256 for each download; check it after the download:

```bash
sha256sum ProArt-X870E-CREATOR-WIFI-ASUS-*.zip   # must match the SHA-256 on the page
```

Some releases cannot be rolled back to an older version (the page says so in their
notes, for example 1804 and 2202). That is no reason to stay on an old one.

**USB stick for BIOS FlashBack.** Any stick of 1 GB or more; it is erased.

1. One partition, MBR partition table, **FAT32**. On Linux (check the device name with
   `lsblk` first; `/dev/sdX` is the whole stick, not a partition):

   ```bash
   sudo parted -s /dev/sdX mklabel msdos mkpart primary fat32 1MiB 100%
   sudo mkfs.vfat -F 32 /dev/sdX1
   ```

   On macOS: Disk Utility, View → Show All Devices, select the stick itself (not its
   volume), Erase, Format **MS-DOS (FAT)**, Scheme **Master Boot Record**. Or in the
   terminal (check the disk number with `diskutil list` first):
   `diskutil eraseDisk FAT32 BIOS MBRFormat /dev/diskN`.

   On Windows: right-click the drive, Format, FAT32. Windows offers FAT32 only for
   sticks up to 32 GB; for a bigger stick use a small one, or format it on Linux or macOS.

   **Not exFAT and not NTFS:** FlashBack does not read them, and the LED stays lit
   (step 5 below). exFAT is the usual default for sticks over 32 GB.
2. Unzip the download. It holds the BIOS file (`.CAP`) and `BIOSRenamer.exe`.
3. Rename the `.CAP` file to **`A5560.CAP`**, the name FlashBack looks for on this board
   (board manual, specifications summary). On Windows `BIOSRenamer.exe` does this; on
   Linux rename it by hand.
4. Copy `A5560.CAP` to the root of the stick, nothing else needed. Eject the stick
   cleanly (`sync`, then `sudo eject /dev/sdX`).

**Flash with BIOS FlashBack** (board manual section 2.7). Works with the machine off,
and even without a working CPU or RAM, so it also works on a board that does not POST:

1. Shut the machine down. Leave the power cord in and the PSU switched on.
2. Put the stick into the rear USB port marked **BIOS FlashBack** (next to the
   FlashBack button on the rear I/O; see the board manual).
3. Press the **BIOS FlashBack button** for about 3 seconds, until its LED blinks three
   times, then let go.
4. Wait until the LED goes out, up to about 8 minutes. During this time do not unplug the
   stick or the power, do not power on, and do not press Clear CMOS.
5. If the LED blinks for about 5 seconds and then stays lit, the flash did not start:
   usually the stick is not FAT32 or the file name is wrong. Power-cycle to clear the
   LED, fix the stick, try again.
6. Power on. The first start after the update takes longer: the board trains the memory
   again (orange DRAM LED, [02](02-assembly.md#first-power-on)). Be patient.

**Alternative: EZ Flash 3,** from inside the BIOS (Tool → ASUS EZ Flash 3 Utility),
reading the `.CAP` file from a USB stick or from the IPMI card's virtual media through
the remote console. Useful when nobody is at the machine; FlashBack needs someone to
press the button.

**After the update:**

- Record the version in the [machine record](machine-record.md).
- The update resets the BIOS settings: set every setting of section 5 again, EXPO to
  Disabled first, and section 2 (firmware display on the IPMI card) if the board's HDMI
  is used again.

### BMC (card) firmware

The latest release is on the card's
[ASUS support page](https://www.asus.com/us/supportonly/ipmi%20expansion%20card/helpdesk_bios/).
In the web console: **Maintenance → Firmware Update**, upload the image, tick
**Preserve all Configuration** (without it every card setting is lost, including both
passwords), start the flash. The card has one firmware slot and no backup: never cut
its power while it flashes. Record the version.

## 7. Verify

```bash
ssh ops@<host address> 'mokutil --sb-state; [ -d /sys/firmware/efi ] && echo UEFI; nvidia-smi -L'
```

Expected: `SecureBoot disabled`, `UEFI`, and, once the driver is installed ([04](04-provisioning.md) Phase 3), both GPUs listed. If `nvidia` is not loaded: `sudo modprobe nvidia`.

## Do NOT

- **Don't try the MOK enrollment blind.** Two attempts failed: the blue screen was on the onboard
  display. With `mokutil --timeout -1` MokManager then waited forever, invisible, with no network,
  until a power cycle. If you ever set the MOK timeout, set it back: `sudo mokutil --timeout 10`.
- **Don't set Primary Video to `IGFX`** – that is the onboard graphics (the default problem).
- **Don't disable CSM** while you need BIOS access through the card; the screen goes dark again.

## If you want Secure Boot ON (MOK route) instead

Only possible if MokManager is visible: either with a monitor on the board's HDMI (onboard
graphics enabled, before section 2), or once ASUS provides a BIOS that accepts the card's UEFI video.

1. `sudo mokutil --import /var/lib/dkms/mok.pub` (set a one-time password), keep `--timeout 10`.
2. Reboot; on the blue screen press a key within 10 s → **Enroll MOK → Continue → Yes →** password → **Reboot**.
3. Verify: `mokutil --test-key /var/lib/dkms/mok.pub` → "is already enrolled".
## Other things to know

- The host has no IP address after the IPMI card goes in: adding a PCIe card shifts the
  network interface names (for example `enp12s0` becomes `enp14s0`), and
  NetworkManager profiles still name the old interfaces. Bind the profiles to MAC
  addresses: `nmcli con modify <profile> connection.interface-name "" 802-3-ethernet.mac-address <mac>`
  ([04](04-provisioning.md) Phase 7 does this for the bond).
- A desktop (GNOME) blanks and locks the screen; the card then reports "no signal".
  Before typing through the remote console, take a screenshot: a locked screen takes
  the typed command as a password attempt.
- Stale web console sessions can block a new login: clear them with
  `GET /api/settings/service-sessions?service_id=1`, then
  `DELETE /api/settings/service-sessions/<id>?service_id=1`.
