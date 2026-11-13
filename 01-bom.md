# 01 BOM: what to buy

The bill of materials for one onprem.ai S2 server. Everything in [03](03-bring-up.md)
to [05](05-acceptance.md) was tested with these parts. Change a part only with a
reason, and write the reason under "Alternatives".

`TODO` marks what has not been recorded yet: fill it in from the order of the next
machine. [bom.csv](bom.csv) is the same list for ordering.

| # | Part | Model | Qty | Part number | Supplier | Notes |
|---|---|---|---|---|---|---|
| 1 | Mainboard | ASUS ProArt X870E-CREATOR WIFI (AM5, X870E) | 1 | TODO | TODO | Two CPU x16 slots that run x8/x8; manuals in [`hardware/mainboard/`](hardware/mainboard/) |
| 2 | CPU | AMD Ryzen 9 9900X, 12 cores | 1 | TODO | TODO | 16 PCIe 5.0 lanes for the two GPU slots |
| 3 | CPU cooler | Thermalright Peerless Assassin 120 Mini, black (air, 135 mm high, one 120 mm PWM fan) | 1 | TODO | TODO | Must hold the CPU below 95 C during a GPU burn (it reaches 84 to 85 C); fits the chassis's 137 mm cooler limit ([`hardware/cpu-cooler/`](hardware/cpu-cooler/)) |
| 4 | RAM | 32 GB DDR5 module, non-ECC, any brand (64 GB in total) | 2 | Any | Any | One module per channel; EXPO only after a memory test ([03](03-bring-up.md)). Tested: Kingston FURY Beast KF560C30-32 |
| 5 | GPU | NVIDIA RTX PRO 6000 Blackwell Server Edition (`10de:2bb5`), 96 GB, passive | 2 | TODO | TODO | No fans of its own: needs items 9 and 17. 267 mm long, 111 mm high, dual slot |
| 6 | NVMe disk 1 | WD_BLACK SN7100 2 TB NVMe by Sandisk (PCIe Gen4 x4, M.2 2280, TLC, 1200 TBW, 5-year warranty) | 1 | WDS200T4X0E | TODO | Goes in M.2_1. RAID 1 mirror with item 7: 2 TB usable for system, weights and images |
| 7 | NVMe disk 2 | WD_BLACK SN7100 2 TB NVMe by Sandisk (same as item 6) | 1 | WDS200T4X0E | TODO | Goes in M.2_3 or M.2_4, never M.2_2 ([slot plan](02-assembly.md#slot-plan)). Same model and size as item 6 |
| 8 | Chassis | SilverStone RM4A (4U rackmount) | 1 | SST-RM4A | TODO | Fan positions: 3x 120 mm front, 2x 80 mm rear (item 18). Limits: GPU 424 mm long, 113 mm high; CPU cooler 137 mm; PSU 255 mm ([`hardware/chassis/`](hardware/chassis/)) |
| 9 | GPU fans | Arctic S12038-8K (120x38 mm, 2.2 A at 12 V) | 2 | TODO | TODO | In series in the GPU fan duct (item 17), front to back, feeding both GPUs; powered from the PSU, not from a board header |
| 10 | Fan power adapters | CRJ Electronics 15-Pin SATA to 4-Pin PWM Fan Power Adapter Cable (25 cm, 20 AWG) | 2 | [4063](https://crjelectronics.com/products/4063?variant=40226517155928) (UPC 850028770092) | CRJ Electronics | One per GPU fan: 12 V from the PSU's SATA connector, PWM and tach passed through from the board header ([02](02-assembly.md), "GPU fans") |
| 11 | PSU | Seasonic PRIME PX-2200 (ATX 3.1, 2200 W, single +12 V rail, fully modular) | 1 | PRIME-PX-2200-ATX30 | TODO | 200 to 240 V input only; two native 12V-2x6 cables; 210 mm long; datasheet and manuals in [`hardware/psu/`](hardware/psu/) |
| 12 | Power cord | C19 plug (for the PSU's C20 inlet), for the local socket | 1 | TODO | TODO | A C13 cord does not fit the PX-2200 |
| 13 | Remote KVM | Sipeed NanoKVM-PCIe (open-source KVM over IP on a PCIe bracket; optional WiFi and PoE modules not needed) | 1 | TODO | TODO | Remote screen, keyboard and mouse, virtual USB drive for OS installs, ATX power and reset (9-pin power header). Powered from the PCIe slot only, not a graphics device: video comes from the board's HDMI output. 100 Mbit Ethernet. [Sipeed wiki](https://wiki.sipeed.com/hardware/en/kvm/NanoKVM_PCIe/introduction.html) |
| 14 | Network | On board: Marvell AQC113 10 GbE, Intel I226-V 2.5 GbE | 0 | | | Both ports cabled, one active-backup bond ([04](04-provisioning.md) Phase 7) |
| 15 | Network cables | Cat6a for 10 GbE, one more for the KVM | 3 | TODO | TODO | Server (2) and KVM (1) |
| 16 | UPS (optional) | 1.5 kW or more, pure sine output | 1 | TODO | TODO | |
| 17 | GPU fan duct | Custom 3D-printed part in front of both GPUs, holds both GPU fans in series | 1 | STL in [`hardware/gpu-fan-duct/`](hardware/gpu-fan-duct/) (TODO) | Printed in-house | Print in Prusament PETG V0 (UL94 V-0, self-extinguishing), natural or black |
| 18 | Rear fans | Arctic P8 Max, black (80 mm, PWM, 500 to 5000 rpm, 0.19 A) | 2 | ACFAN00286A | TODO | The chassis's two 80 mm rear positions, behind the CPU, blowing out; on board headers ([`hardware/rear-fans/`](hardware/rear-fans/)) |
| 19 | Rack rails (optional) | SilverStone RMS05-22 (ball-bearing slide rails, 611 mm, 2.8 kg) | 1 kit | SST-RMS05-22 | TODO | Only for rack mounting. The RM4A takes no standard rails: this kit only. Rack hole distance 595 to 936 mm ([`hardware/rack-rails/`](hardware/rack-rails/)) |
| 20 | Chassis fans, front | 120 mm PWM fan, lower power than the GPU fans (model TODO) | 2 | TODO | TODO | Front positions of the chassis (item 8), blowing in (front to back); on board headers. Position TODO |
| 21 | Fan grills, 120 mm | 120 mm fan grill (model TODO) | 3 | TODO | TODO | For the three 120 mm front positions |
| 22 | Fan grills, 80 mm | 80 mm fan grill (model TODO) | 2 | TODO | TODO | For the two 80 mm rear fans (item 18) |
| 23 | Fire suppression in the chassis (optional) | MAUS Switzerland Handfeuerlöscher Stixx «Pro», fire class ABCF (self-triggering potassium aerosol, 9.8 x 1.8 x 1 cm, 26 g) | 1 | 1350-1 (EAN 7350015530164) | MAUS Switzerland | Triggers by itself at 170 to 180 C, no power needed; leaves no residue on electronics. Protects up to 0.1 m³, the chassis is about 0.035 m³: one is enough. Stick it to the inside of the chassis lid, holes facing down, 2 to 3 cm free in front of them, away from the fan intakes. Replace after 5 years: note the date in the machine record |
| 24 | BMC (optional, replaces item 13) | ASUS IPMI Expansion Card-SI (ASPEED AST2600) | 1 | 90MC0AH0-MVUBY0 / -MVUBY1 | TODO | Full IPMI/Redfish BMC with its own video. Board revision R1.04, all cables in the box ([`hardware/ipmi-card/`](hardware/ipmi-card/)). On this board without in-band access (needs a special BIOS from ASUS support) |

## Tested configuration

Tested with Rocky Linux 10.2 (kernel 6.12) and Ubuntu 24.04 (kernel 6.17).

| Part | Model |
|---|---|
| Board | ASUS ProArt X870E-CREATOR WIFI (AM5, X870E) |
| CPU | AMD Ryzen 9 9900X, 12 cores |
| RAM | 2x 32 GB DDR5 (two modules, one per channel) |
| GPUs | 2x NVIDIA RTX PRO 6000 Blackwell Server Edition (`10de:2bb5`, passive, 600 W stock) |
| Storage | 2x 2 TB WD SN7100 NVMe in one RAID 1 mirror ([RAID 0 option](options/raid0-compute-only.md) for compute-only nodes) |
| GPU fans | 2x Arctic S12038-8K, each powered by its own SATA power feed from the PSU, PWM and tach on board headers |
| Out-of-band | ASUS IPMI Expansion Card-SI (ASPEED AST2600); the standard is now the Sipeed NanoKVM-PCIe (item 13), not yet tested |
| Network | Marvell AQtion AQC113 10 GbE (`atlantic`) and Intel I226-V 2.5 GbE (`igc`), both in one active-backup bond with the 10 GbE port as primary ([04](04-provisioning.md) Phase 7) |
| PSU | Seasonic PRIME PX-2200 (ATX 3.1, 2200 W, one +12 V rail of 183.3 A); each GPU on its own native 12V-2x6 cable (600 W) |

## Why these parts

- **Board and CPU:** an AM5 platform with two CPU-attached x16 slots. The two
  GPUs run at Gen5 x8 each, which is the normal state on this platform, not a fault.
  The trade-off: no PCIe switch and no NVLink, so GPU-to-GPU DMA crosses the CPU's PCIe
  root complex, at x8 per GPU, and needs `iommu=pt` ([04](04-provisioning.md) Phase 4).
- **Passive server-edition GPUs:** they rely on chassis airflow. The board's fan curves
  never see GPU temperature, hence the dedicated GPU fans and fan2go
  ([04](04-provisioning.md) Phase 6, [260720](learnings/260720-gpu-fan-hub-alphacool-es-guardian.md)).
- **Remote KVM, Sipeed NanoKVM-PCIe instead of the ASUS IPMI card:** remote access is
  the only way back into a hung machine or its BIOS without a person at the console. The
  ASUS card (item 24) is listed as compatible with the board, but its IPMI function needs
  a special BIOS that is not published anywhere, ASUS support and developer experience
  are poor, and its remote console software is hard to automate (switching screens is
  cumbersome). The NanoKVM is open source with a broad community that keeps its
  software current, and it integrates natively with MCP for AI agents. What it does not
  have: its own graphics device, board sensors or Redfish; it captures the board's HDMI
  output and switches power through the front panel header.

### Power budget

The Seasonic PRIME PX-2200 has a single +12 V rail
([Seasonic datasheet](https://seasonic.com/wp-content/uploads/2025/03/Prime-PX-2200-v2.pdf), copy in [`hardware/psu/`](hardware/psu/)).
That rules out a known failure of multi-rail units: a GPU's
current spike trips one rail's over-current protection and the machine goes dark with
no log entry ([260526](learnings/260526-gpu-pcie-drop-recovery.md), "PSU Power
Delivery"). The budget at the 500 W power limit ([04](04-provisioning.md) Phase 3): 2x 500 W of GPU, up to 162 W of CPU
(the Ryzen 9 9900X's package power limit), about 50 W for the two GPU fans at full
speed and some 50 W for board, memory and disks: about 1.3 kW, well inside 2200 W,
also for the GPUs' short spikes above their limit.

- AC input is 200 to 240 V only, through a C19 cord: a 230 V socket on a circuit of
  at least 10 A (16 A recommended), never a 115 V outlet.
- Use the two native 12V-2x6 cables, one per GPU, never the 2x 8-pin adapter cables.
  Both ends fully inserted and clicked in, no sharp bend next to the connector.
- The two GPU fans are powered from the PSU's SATA cables ([02](02-assembly.md), "GPU fans").
- On a UPS: size it for 1.5 kW and pure sine output.

## Alternatives

None tested yet. Record a substitute here with what was checked: the
[05 Acceptance](05-acceptance.md) checks passed with it.
