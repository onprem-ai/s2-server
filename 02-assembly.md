# 02 Assembly: putting the S2 together

From the parts of the [BOM](01-bom.md) to a machine that powers on and shows POST. Work
on an anti-static mat, PSU switched off and unplugged. Board manual:
[`hardware/mainboard/E28680_ProArt_X870E-CREATOR_WIFI_EM_V2_WEB.pdf`](hardware/mainboard/E28680_ProArt_X870E-CREATOR_WIFI_EM_V2_WEB.pdf).

TODO, to be completed while building the next S2: photos (`photos/`), the case-specific
steps, torque and cable routing.

## Slot plan

The Ryzen 9000 gives 16 PCIe 5.0 lanes for the two x16 slots, shared with M.2_2
([ASUS specifications](https://www.asus.com/us/motherboards-components/motherboards/proart/proart-x870e-creator-wifi/techspec/)).

| Slot | Device | Link | Lanes from |
|---|---|---|---|
| PCIEX16(G5)_1 | GPU 0 (`01:00.0`) | Gen5 x8 | CPU |
| PCIEX16(G5)_2 | GPU 1 (`03:00.0`) | Gen5 x8 | CPU |
| M.2_1 | NVMe disk 1 (RAID 1 member, `02:00.0`) | Gen4 x4 (Gen5 capable slot) | CPU |
| M.2_2 | Empty, always | | Shares lanes with PCIEX16(G5)_2 and the USB4 ports; a disk here drops GPU 1 to x4 |
| M.2_3 or M.2_4 | NVMe disk 2 (RAID 1 member) | Gen4 x4 | Chipset |

The two disks are one RAID 1 mirror ([04](04-provisioning.md) Phase 1). One on CPU
lanes and one on chipset lanes is fine for a mirror: both run at Gen4 x4.
| PCIEX16(G4) | IPMI Expansion Card | Gen3 x1 | Chipset |

A disk in M.2_2 shows as an NVMe on root port `00:01.4` with GPU 1 at Gen5 x4
(`lspci -tv`, the link width check in [05](05-acceptance.md)). Move it to M.2_3 or M.2_4.

Two GPUs at x8 each is the normal state on this platform, not a fault. The two GPUs
are on separate root ports of the CPU. Peer-to-peer DMA goes directly from one GPU to
the other over the CPU's PCIe root complex (not through CPU cores or system memory),
and `iommu=pt` is required for it ([04](04-provisioning.md) Phase 4). The IPMI card's BMC cable to the board's BMC header
gives the card the board's sensors. The SPI cable to the TPM/SPI header is for BIOS
updates through the card, which ASUS does not support on this board
([compatibility list](hardware/ipmi-card/README.md#what-the-card-can-do-on-the-s2s-board)); connect it anyway, it is harmless.
Its configuration and the password change of `Administrator` and `admin` are in
[03 Bring-up](03-bring-up.md).

## Airflow

All air in the S2 moves front to back:

- **GPUs:** the GPU fan duct sits in front of the two GPUs and holds both 120 mm GPU
  fans in series, one directly behind the other. The single air stream goes through
  both GPUs at once and leaves through their slot brackets at the rear.
- **CPU:** the CPU cooler blows towards the rear, where the two 80 mm rear fans take
  the air out.

Nothing in the chassis blows back to front. Every fan's arrow on its frame points
towards the rear of the chassis.

## Build order

Start with the mainboard outside the chassis, on its box or the anti-static mat.

> **The GPUs go in only after all the wiring is done and tested (steps 9 and 10).**
> Two dual-slot, full-length GPUs fill most of the board and the space around it. Once they are in,
> the fan headers, the front panel and USB headers, the IPMI card's BMC and SPI
> headers and the M.2 slots are under or behind them, with no room for fingers. Every
> cable plugged in after the GPUs means taking them out again.
>
> Before step 9, check that each of these is connected and routed clear of the two
> GPU slots:
>
> - 24-pin mainboard and both 8-pin CPU power cables (CPU_12V_1, CPU_12V_2)
> - PSU Hybrid Mode off (Normal)
> - IPMI card: BMC cable, SPI cable with TPM adapter, USB 2.0 cable, power and reset
>   cables to the board and from the chassis buttons, 6-pin PCIe power
> - Both GPU fan cables: SATA power from the PSU, adapter on the header of channel 4
>   and of channel 6
> - CPU cooler fan on CPU_FAN, both rear fans on their chassis headers
> - The chassis front panel (power switch, LEDs) and USB cables
> - The two 12V-2x6 cables in the PSU and laid out to where the GPU power sockets will
>   be, the GPU ends tied clear of the board
> - Both NVMe disks in, M.2_2 empty

1. **CPU** into the socket.
2. **CPU cooler** (Thermalright Peerless Assassin 120 Mini), with its fan blowing towards
   the rear of the chassis, where the rear fans take the air out. Its fan cable to
   CPU_FAN.
3. **RAM:** the two modules in the slots the board manual names for two modules (one per
   channel).
4. **NVMe disks**, while the board is still outside the chassis: disk 1 in M.2_1,
   disk 2 in M.2_3 or M.2_4, M.2_2 empty. The two become one RAID 1 mirror in the OS
   install. The slot decides the PCIe lanes
   (see the [slot plan](#slot-plan)): M.2_1 has its own CPU lanes; M.2_2 shares its lanes
   with the second GPU slot, so a disk there drops GPU 1 from x8 to x4; M.2_3 and M.2_4
   hang off the chipset and take nothing from the GPUs.
5. **Mainboard into the chassis**, I/O shield first if the case needs one. The two
   80 mm rear fans (Arctic P8 Max) in the chassis's rear positions behind the CPU,
   blowing out; their cables to two free chassis fan headers, not the two headers kept
   for the GPU fans (step 8).
6. **IPMI card** in PCIEX16(G4), with its two chassis cables to the board: BMC and SPI
   (below).
7. **PSU** in, then its cables: the IPMI card's PCIe power, the 24-pin mainboard, both
   8-pin CPU power cables (CPU_12V_1 and CPU_12V_2, one PSU cable each), and the two
   native 12V-2x6 GPU cables at the PSU end, routed to where each GPU's power socket
   will be. Tie the GPU ends clear of the board and the chassis: they carry 12 V during
   the test in step 9. Check the input voltage: the PX-2200 takes 200 to 240 V only.
   With the PSU's I/O switch off (`O`), set its **Hybrid Mode** button on the back to
   off ("Normal"): the PSU fan then always runs ([PSU](hardware/psu/README.md)).
8. **GPU fan cables**, before the GPUs cover the headers: SATA power from the PSU for each
   fan, PWM and tach to the two GPU fan headers, the ones Linux reads as fan channels 4
   and 6, one fan per header (below).
9. **IPMI and power test**, still without the GPUs: proves the IPMI card and the front
   panel can both switch the machine on, reset it and switch it off
   ([below](#ipmi-and-power-test)). Ends with the power cord unplugged.
10. **GPUs**, last of all the parts on the board: only now, with every cable from steps 6
    to 8 connected, routed and tested in step 9. In PCIEX16(G5)_1 and PCIEX16(G5)_2,
    fully seated, bracket screwed down.
11. **GPU power cables** into the GPUs: the cables laid in step 7, one per GPU (below),
    before the fan duct blocks the connectors. Each one fully clicked in.
12. **GPU fan duct** in front of the two GPUs: the 3D-printed part that holds both fans
    in series ([`hardware/gpu-fan-duct/`](hardware/gpu-fan-duct/)).
13. **GPU fans** in the duct, one directly behind the other, both blowing towards the
    GPUs (front to back; check the arrow on each frame). Connect them to the cables
    from step 8.
14. **Power on** (below). Before that, the network: both board ports (10 GbE and 2.5 GbE)
    to the switch, the IPMI card's own LAN port to the management network.

## IPMI card

Card manual, section 2.2, and every connector in
[`hardware/ipmi-card/`](hardware/ipmi-card/); also the
[ASUS installation guide](https://zentalk.asus.com/t5/faq/the-installation-guide-of-ipmi-expansion-card-for-all-compatible/ta-p/472925).

- Card in PCIEX16(G4).
- BMC cable from the card's BMC header to the board's BMC header: the board's sensors
  in the card's web console.
- SPI cable from the card to the SPI Adapter FPC (SPI_BMC side), the adapter's SPI_MB
  side on the board's TPM/SPI header. For BIOS updates through the card, which ASUS does
  not support on this board yet; connected anyway, ready if that changes.
- USB 2.0 cable from the card to a USB 2.0 header on the board: required, it powers the
  card, and carries the remote console's keyboard and mouse, virtual media and the
  host's USB link to the card.
- Power on/off and reset cables: the **shorter** end on the card's PANEL header (MB
  pins), the **longer** end on the power and reset pins of the board's front panel
  header (F_PANEL: PWR_BTN and RESET). On the card the red wire is nearest the card's
  PCB; on the board the two cables sit opposite ways round, with the **black wire on the
  GND pin**.
- **Polarity matters on these two cables, between card and board.** A plain chassis
  button works either way round; the card's cables do not, because the card switches
  the line electronically. Wrong way round, the board does not react to the power or
  reset button, and not to the card either. Then turn that cable's plug on the board's
  header round (swap + and −) and test again. Each cable separately: power can be right
  while reset is wrong.
- The chassis's power and reset buttons to the card's PANEL header (CHA pins), through
  the two bundled 2-pin adapter cables (2.54 mm to 2.0 mm pitch).
- The IPMI and power test (step 9) proves this wiring.
- The card is board revision **R1.04** (printed on the PCB). Use the R1.04 quick start
  guide for where each header sits: the older guides show the R1.01 layout.
- The card's 6-pin PCIe power from the PSU, connected with the PSU in step 7.
- Jumpers stay at their defaults (BMC and VGA enabled, LAN IP by DHCP).

## IPMI and power test

Step 9, before the GPUs go in: if a power, reset or BMC cable is wrong, it can still be
reached. The NVMe disks are still empty, so the machine has nothing to boot and every
start ends in the BIOS. Until [03 Bring-up](03-bring-up.md) section 2 moves the firmware
display to the IPMI card, the BIOS shows only on the board's own HDMI: keep a monitor
there to see each start.

1. **Network:** a LAN cable from the IPMI card's own LAN port to the management
   network (not a shared network: the card still has its default passwords).
2. **Power:** plug in the power cord, PSU switch on. The machine stays off; the card
   starts on standby power (allow it a minute or two).
3. **Log in:** open the card's web console in a browser, over **https**
   (`https://<card address>`; the address comes from DHCP, find it by the card's MAC).
   User `admin`, password `admin`.
4. **New password:** the card asks for a new password right away. Have the password
   manager open and store it there before you confirm it (the entry name goes in the
   [machine record](machine-record.md); never the password itself). **8 to 16
   characters, no spaces.** By default the card stores at most 16 characters: a longer
   password is cut off without any message, and the full one you saved is then refused
   at the next login, which looks as if the password was never accepted. Use 16 or
   fewer, for both accounts.
5. **Second account:** the card has a second administrator account, `Administrator`,
   with its own default password (`superuser`), and the first login does not change
   it. Anyone who knows that default has the machine's power, console and boot media.
   In the web console: **Settings → User Management**, edit `Administrator`, tick
   **Change password**, set a new password, store it in the password manager too.
   Then log out and check that `Administrator` / `superuser` is refused.
6. **IPMI power on, into the BIOS:** from the card's power menu, power the machine on.
   It must start into the BIOS.
7. **IPMI reset:** reset from the card's power menu. It must start into the BIOS again.
8. **IPMI power off:** power off from the card's power menu. The machine goes off.
9. **Front panel power on:** keep the card's web console open in the browser. Press
   the chassis power button. The machine must start into the BIOS, and the card's web
   console must show it as on.
10. **Front panel reset:** press the chassis reset button. It must start into the BIOS
    again.
11. **Front panel power off:** press the power button (hold it if the machine does not
    react to a short press). The machine goes off, and the card shows it as off.
12. **Discharge:** unplug the power cord, then press the front panel power button once
    to drain the power left in the PSU and the board.

Every step must pass. When the machine does not react to power on or reset (from the
card or from the front panel), first turn round the plug of that cable (power or
reset) on the board's front panel header: swap + and −, see "IPMI card" above. That is
the usual cause. Then check the BMC cable and the front panel cable, before the GPUs
make them hard to reach. Only then go on
with step 10, the GPUs.

## GPU fans

The two fans sit in series in the GPU fan duct and feed both GPUs together
([Airflow](#airflow)). Both must blow the same way: one turned around works against
the other.

High-pressure server fans draw more current than a board fan header gives (an Arctic
S12038-8K draws 2.2 A at 12 V, 3.2 A peak; a header gives about 1 A). Power them from
the PSU and give the header only the signal:

- One SATA-to-4-pin fan adapter per fan ([BOM](01-bom.md) item 10): its SATA plug takes
  12 V from the PSU, its female 4-pin end goes on the board header and passes only PWM
  and tach through, and the fan plugs into its male 4-pin end.
- PWM and tach: GPU fan A to the header of fan channel 4, GPU fan B to the header of
  fan channel 6, one fan per header, so each fan has its own RPM reading. These are the
  channels of the S2 standard fan2go configuration ([04](04-provisioning.md) Phase 6).
  TODO: the silkscreen names of these two headers (CHA_FAN1 to CHA_FAN5); the channel
  numbers do not follow the header numbers.
- [04](04-provisioning.md) Phase 6 confirms the channels by test after the OS install.
  Record the headers in the [machine record](machine-record.md).
- Lay these cables in step 8, before the GPUs go in: the GPUs cover the headers.
- Never power these fans from a header: its fuse trips, and the fan stops and starts
  every few seconds ([260720](learnings/260720-gpu-fan-hub-alphacool-es-guardian.md)).

## GPU power

- The two native 12V-2x6 cables of the PSU, one per GPU. Never the 2x 8-pin adapter
  cables, never one cable daisy-chained to both.
- Both ends fully inserted and clicked in, no sharp bend next to the connector.

## Checks before the first boot

- Each GPU in an x16 slot wired to the CPU, not to the chipset.
- 12V-2x6 / 12VHPWR connectors fully seated; one cable per GPU connector, no daisy chain.
- Passive (server edition) cards: chassis airflow is designed for them. They have no
  fans of their own and throttle or shut down in a workstation case
  ([260720](learnings/260720-gpu-fan-hub-alphacool-es-guardian.md)).
- M.2_2 empty.
- IPMI and power test passed (step 9), the power cord was unplugged for the GPUs.
- All IPMI card cables in place: BMC, SPI, USB 2.0, power and reset, 6-pin power.
- Both 8-pin CPU power plugs in; the board's CPU_12V_LED (next to them) is off once
  power is on. PSU Hybrid Mode off.

## First power-on

1. Monitor on the board's HDMI, keyboard attached: [03 Bring-up](03-bring-up.md)
   section 2 needs them once.
2. Power on. Watch the Q-LEDs. **Be patient:** on the first start, and after any RAM
   change or Clear CMOS, the board trains the memory, and the orange DRAM LED can stay
   lit for several minutes with a dark screen. That is normal: do not power off or reset.
   Only if it is still lit after about 10 minutes, power off and reseat the RAM. The IPMI
   card already has new passwords for both accounts from step 9.
3. In the BIOS, on the first page (EZ Mode): set **EXPO to Disabled**, so the RAM runs
   at its JEDEC default, then **F10**. With EXPO on, the RAM can be unstable without any
   warning, and the OS installer then crashes at random places
   ([261026](learnings/261026-installer-crashes-unstable-ram.md)). Turn EXPO on only
   after a memory test passes ([03](03-bring-up.md) section 5).
4. Still in the BIOS: both GPUs and both NVMe disks are listed, the RAM is complete.
5. **BIOS version:** shown on the first BIOS page. If it is older than the latest
   release on the ASUS support page, update it now, before the OS install, with BIOS
   FlashBack ([03 Bring-up](03-bring-up.md#6-firmware-updates)). Afterwards set EXPO
   to Disabled again: the update resets the BIOS settings.
6. Note the serial numbers, the MAC addresses of both ports and of the IPMI card in the
   [machine record](machine-record.md).

For a rack: first [03 Bring-up](03-bring-up.md) section 2 on the bench, then
[into the rack](#into-the-rack-optional).

## Into the rack (optional)

Only for a rack. The RM4A takes no standard rails: use the SilverStone RMS05-22 kit
([BOM](01-bom.md) item 19, manual in [`hardware/rack-rails/`](hardware/rack-rails/)).
Check before ordering that the rack's front and rear mounting holes are 595 to 936 mm
apart.

Rack the machine after the first power-on and after [03 Bring-up](03-bring-up.md)
section 2, which needs a monitor and keyboard at the board once; on the bench that is
easier than in the rack. Everything after that goes through the IPMI card.

1. **Power off and unplug** the power cord and all network cables.
2. **Inner members on the chassis:** release the inner member from each rail and fix
   it to the side of the chassis.
3. **Outer members in the rack:** click each rail's outer member into the front and
   rear mounting holes at the same height on both sides. Use the screw holes as well
   for extra hold.
4. **Slide the chassis in:** pull the middle members out until they lock, with the
   ball-bearing retainer at the front. Two people: the S2 weighs about 18 to 20 kg.
   Set the chassis's inner members into the middle members, push until the stop,
   press the release tab, and slide the chassis home.
5. **Cables:** the power cord, both board network ports to the switch, the IPMI card's
   LAN port to the management network. Leave enough slack to pull the chassis out on
   its rails without unplugging anything.
6. **Airflow:** the front of the chassis (the GPU fan duct's intake) faces the cold
   aisle, the rear fans the hot aisle. Nothing blocks the front or the rear.

To take the chassis out again: pull it out until the rails lock, then pull the
release tabs forward and lift it off.

Continue with [03 Bring-up](03-bring-up.md).
