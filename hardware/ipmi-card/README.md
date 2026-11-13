# IPMI card: ASUS IPMI Expansion Card-SI

The S2's BMC: a PCIe card with its own LAN port, web console, remote console (KVM),
virtual media and IPMI 2.0. Chip: ASPEED AST2600. ASUS part number 90MC0AH0-MVUBY0 /
-MVUBY1. [Support page](https://www.asus.com/us/supportonly/ipmi%20expansion%20card/helpdesk_bios/)
(firmware downloads; current release 1.3.13, 2026-02-26).

| File | What | Source |
|---|---|---|
| [ASUS_IPMI_Expansion_Card_user_manual_E26328_V3.pdf](ASUS_IPMI_Expansion_Card_user_manual_E26328_V3.pdf) | User manual E26328, revised edition V3, July 2025 (148 pages) | [dlcdnets.asus.com](https://dlcdnets.asus.com/pub/ASUS/mb/Add-on_card/IPMI_EXPANSION_CARD/E26328_IPMI_Card_EM_V3_WEB.pdf) |
| [ASUS_IPMI_Expansion_Card_QSG_R1.04_E21524_V2.pdf](ASUS_IPMI_Expansion_Card_QSG_R1.04_E21524_V2.pdf) | Quick start guide E21524, V2, March 2023: the guide for board revision **R1.04**, with its header layout | [dlcdnets.asus.com](https://dlcdnets.asus.com/pub/ASUS/mb/Add-on_card/IPMI_EXPANSION_CARD/E21524_IPMI_Card_QSG_V2_WEB.pdf) |
| [ASUS_IPMI_Expansion_Card_compatible_models_2025-11.pdf](ASUS_IPMI_Expansion_Card_compatible_models_2025-11.pdf) | ASUS compatibility list, 2025-11-03: which boards get sensor monitoring and remote BIOS update | [dlcdnets.asus.com](https://dlcdnets.asus.com/pub/ASUS/mb/Add-on_card/IPMI_EXPANSION_CARD/Compatible_Model_List.pdf) |
| [ASUS_IPMI_Expansion_Card_FAQ_E26329_V2.pdf](ASUS_IPMI_Expansion_Card_FAQ_E26329_V2.pdf) | FAQ E26329, V2: `ipmitool` on Windows and Linux, password reset, fan commands | [dlcdnets.asus.com](https://dlcdnets.asus.com/pub/ASUS/mb/Add-on_card/IPMI_EXPANSION_CARD/E26329_IPMI_Card_FAQ_EM_V2_WEB.pdf) |

The three documents ASUS lists on the card's
[manual page](https://www.asus.com/us/supportonly/ipmi%20expansion%20card/helpdesk_manual/)
(all dated 2025-07-29), downloaded 2026-10-24.

Remote provisioning through this card (screen, mouse, keyboard, power, BIOS, card
firmware) for an AI agent: [asus-ipmi-mcp](https://github.com/onprem-ai/asus-ipmi-mcp),
an MCP server in its own repository.

## Board revisions

The card exists in at least two board revisions, printed on the PCB: **R1.01** and
**R1.04**. Both have the same headers, but in different places on the board; the
firmware is the same for both. The S2 has **R1.04**: follow the R1.04 quick start guide
(E21524) for where each header sits. The older first-edition user guide (E19387,
February 2022) and the R1.01 quick start guide (E21362) show the R1.01 layout: do not
use their drawings for an R1.04 card.

R1.04 is the latest revision on record (October 2026): ASUS's current quick start guide
is the R1.04 one, every card photographed in 2025–2026 reports is R1.04, and ASUS's
store lists one card, 90MC0AH0-MVUBY0/-MVUBY1, with no newer revision. A future card on
the AST2700 chip would be a new product, not a revision of this one. Check the
revision printed on each card on arrival and record it in the machine record.

R1.04 also differs in the box: the SPI cable goes through an **SPI Adapter FPC** (a
flat cable board, SPI_BMC side to the card, SPI_MB side to the board's TPM header),
and the chassis power and reset leads reach the card's CHA pins through **two 2-pin
adapter cables** (2.54 mm pitch to 2.0 mm pitch), also in the box.

## Where to look in the manual

Page numbers are those of the user manual E26328 V3 PDF.

| Topic | Section | PDF page |
|---|---|---|
| Package contents, specifications | 1.2, 1.3 | 10–11 |
| Every connector and what it is for | 1.4 | 12–13 |
| Jumpers | 1.7 | 18 |
| Hardware installation, cable by cable (header positions: R1.04 quick start guide) | 2.2 | 22–26 |
| BIOS: Server Mgmt / IPMI menu, **In-Band driver type**, BMC network (only with the special IPMI BIOS, [below](#access-from-the-host-in-band-needs-the-special-ipmi-bios)) | 2.3 | 27–31 |
| `ipmitool` on Windows and Linux, from the host and over the network | 2.4 | 34–37 |
| Resetting the card's login password | 2.5 | 38–39 |
| First login, password change | 3.1.1 | 42 |
| Firmware update, preserve configuration, restore factory defaults, BIOS update over the network | 3.12 | from 118 |

## In the box

For R1.04 (quick start guide E21524): the card, a BMC cable, an SPI cable, an IPMI TPM
adapter (SPI Adapter FPC), a power on/off cable, a reset cable, two 2-pin adapter cables
(2.54 mm to 2.0 mm pitch) for the chassis buttons, a USB 2.0 cable, a half-height
bracket, and the quick start guide.

## Connections

| Connection on the card | To | What it gives | S2 |
|---|---|---|---|
| PCIe 3.0 x1 edge | Board slot PCIEX16(G4) | The card's graphics, and the IPMI interface the host's `ipmitool` uses ([04](../../04-provisioning.md) Phase 1) | Yes |
| USB 2.0 connector | A USB 2.0 header on the board | Power for the card (ASUS: "make sure to connect"), keyboard and mouse of the remote console, virtual media, the host's USB network link to the card | Yes, required |
| 6-pin PCIe power | PSU | 12 V for the card's eight fan headers | Yes |
| BMC header | Board's BMC header | The board's sensors in the card's web console | Yes |
| SPI header | SPI cable to the SPI Adapter FPC (SPI_BMC side); the adapter's SPI_MB side on the board's TPM/SPI header | BIOS update through the card, **on supported boards only: not the ProArt X870E-CREATOR WIFI** (see below) | Optional on the S2 |
| PANEL header, MB pins | Board's front panel header, power and reset pins | Power on, off and reset from the card | Yes |
| PANEL header, CHA pins | The chassis's power and reset buttons, through the two bundled 2-pin adapter cables | The front panel buttons pass through the card to the board | Yes |
| LAN (RJ45, 1 GbE) | Management network | Web console, IPMI over LAN, Redfish | Yes |
| D-Sub VGA | Monitor | The card's own video output | Not used |
| Fan headers 1–8 | Fans | Fans the card monitors and controls | Not used: all S2 fans are on board headers |
| T_SENSOR 1–3, PSU PM_BUS | Sensors, a PSU with PMBus | Extra temperatures, PSU readings | Not used |

Power on/off and reset cables (manual 2.2, steps 4 and 5):

- The **shorter** end of each cable goes on the card's MB pins, the **longer** end on
  the board's front panel header.
- On the card, the red wire is nearest the card's PCB.
- On the board's header, the two cables sit opposite ways round; the **black wire goes
  on the Ground (GND) pin**. Pin map: board manual section 16, System Panel header
  (F_PANEL), PWR_BTN and RESET.
- **Polarity matters** on the two card-to-board cables, unlike a plain chassis button:
  the card switches the line electronically. Wrong way round, the board ignores the
  power or reset button and the card's power control. Fix: turn that plug round on the
  board's header (swap + and −). Check power and reset separately. The IPMI and power
  test ([02](../../02-assembly.md) step 9) catches it.

## Jumpers

| Jumper | Default | Other position | S2 |
|---|---|---|---|
| BMC_SW | Enable | Disable: the card's BMC off | Enable |
| VGA_SW | Enable | Disable: the card's video off | Enable: the S2's firmware display runs on it ([03](../../03-bring-up.md)) |
| DM_IP_SEL1 (LAN IP mode) | Not fixed: DHCP | Fixed IP 10.10.10.10 | Default. Fixed is a fallback when no DHCP server is at hand |
| SMART_PSU | Disable | Enable: PSU readings over PMBus | Disable |

## Key facts for the S2

| Item | Value | Where it matters |
|---|---|---|
| First login | `https://<card address>`, user `admin`, password `admin`; the card forces a new password at once, for `admin` only | [02](../../02-assembly.md) step 9 |
| Second administrator account | `Administrator`, default password `superuser` (ASMB10-iKVM manual, 3.1.1). Not changed by the first login: change it by hand, Settings → User Management | [02](../../02-assembly.md) step 9 |
| Password rules | 8 to 16 characters, no spaces. The default "Password Size" is 16: a longer password is cut off without a message, so the saved full one is refused at the next login | [02](../../02-assembly.md) step 9 |
| User accounts | Up to 10, including `admin`, `Administrator` and the anonymous user | [03](../../03-bring-up.md) section 1 |
| Start-up after power is plugged in | About 70 seconds before the card answers | [02](../../02-assembly.md) step 9 |
| Card address | Not in the public BIOS (no Server Mgmt menu). Find it by the card's MAC in the DHCP server's leases; then set a static IPv4 address, outside the DHCP range | [03](../../03-bring-up.md) section 1 |
| IPv6 | Off: managed over IPv4 only, so no IPv6 address the card picks up by itself | [03](../../03-bring-up.md) section 1 |
| Factory defaults | Web console: Maintenance, Restore Factory Defaults (keeps what "Preserve Configuration" ticks); from the host only with the special IPMI BIOS: `ipmitool raw 0x32 0x66` ([ASUS FAQ](https://www.asus.com/support/faq/1047906/), not in the manual) | Lost password |
| Firmware update | Web console, Maintenance, Firmware Update; without "Preserve all Configuration" every setting is lost, and the admin password must be set again afterwards | [03](../../03-bring-up.md) section 6 |
| BIOS update through the card | Web console, Maintenance, BIOS OOB Update: upload a `.cap` file, then Power Reset; needs the SPI cable. **Not supported on the S2's board** (see below) | [03](../../03-bring-up.md) section 6 |
| Operating systems | Windows 10 64-bit, Linux (CentOS, Red Hat, Ubuntu named) | |

## What the card can do on the S2's board

ASUS's compatibility list (2025-11-03) for the **ProArt X870E-CREATOR WIFI**:

| Feature | Supported | Needs |
|---|---|---|
| Board sensors in real time | Yes | BMC cable |
| Remote BIOS forced update | **No** | (BMC and SPI cables, on boards that support it) |

So on the S2 the card gives remote console, virtual media, power control and the
board's sensors, but it cannot flash the BIOS. Update the BIOS with the board's own
tools ([03](../../03-bring-up.md) section 6). The SPI cable can stay connected; it is
harmless, and ready should ASUS add support with a later BIOS.

## Access from the host (in-band): needs the special IPMI BIOS

The card manual (2.3, 2.4) describes a BIOS menu **Server Mgmt** (or IPMI) with
**In-Band driver type** (Windows or Linux) and the BMC network settings. Through it,
root on the host reaches the card with `ipmitool`, without network and without the
card's password.

**The public BIOS of the ProArt X870E-CREATOR WIFI has no such menu** (checked on BIOS
2503: no Server Mgmt tab, nothing under Advanced, BIOS search for "IPMI" finds
nothing). ASUS's compatibility list (footnote 1): on this board the IPMI function needs
a special BIOS, available only from ASUS support, and once flashed the board cannot go
back to the public BIOS.

On the public BIOS, Linux finds the card on PCIe, but it does not answer:
`ipmi_si 0000:08:01.0: Interface detection failed`, no `/dev/ipmi0`. Everything that
goes through `ipmitool` on the host does not work there: the password reset and the
factory reset below, and `ipmitool mc info`. Remote console, virtual media, power
control and `ipmitool` over the network (`-I lanplus`) work without it.

## Lost password

**On the public BIOS, a lost card password cannot be reset from the host.** The card
has no reset jumper or button. Keep both card accounts' passwords in the password
manager from the first login on ([02](../../02-assembly.md) step 9). If one is lost:
ask ASUS support (card serial number at hand), or move the card for the reset into a
board where its IPMI function works.

With the special IPMI BIOS, ASUS's own procedure (user manual 2.5, FAQ): In-Band driver
type at Linux, then on the host as root:

```sh
ipmitool user list 1                         # the user IDs
ipmitool user set password <user ID>         # prompts for the new password
```

Error `0x03`: the password is too short; `0x19`: it equals the old one. The card's
other settings stay. The full factory reset (`ipmitool raw 0x32 0x66`) is in ASUS's
[web FAQ](https://www.asus.com/support/faq/1047906/), not in the manual, and wipes every
card setting. The web console's "I forgot my password" works only with a user email
and SMTP set up in the card beforehand.
