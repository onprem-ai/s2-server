# Machine record: template

> **Empty template. Do not fill it in here.** This repository is generic and holds no
> data about specific machines ([CLAUDE.md](CLAUDE.md)). Copy this template to the
> **fleet repository** (a separate repository with one record per machine) and fill it
> in there.

One record per S2, filled in during [02 Assembly](02-assembly.md) to
[05 Acceptance](05-acceptance.md). **Never
write a password into a record**: only the name of the password manager entry that
holds it.

## Identity

| Field | Value |
|---|---|
| Host name (`ain-xxxxx`) | |
| Customer / location / rack | |
| Assembled by, date | |
| Handed off by, date | |

## Hardware

| Part | Model | Serial number |
|---|---|---|
| Board | ASUS ProArt X870E-CREATOR WIFI | |
| CPU | AMD Ryzen 9 9900X | |
| RAM | 2x 32 GB DDR5 | |
| GPU 0 (PCIEX16(G5)_1, `01:00.0`) | RTX PRO 6000 Blackwell Server Edition | |
| GPU 1 (PCIEX16(G5)_2, `03:00.0`) | RTX PRO 6000 Blackwell Server Edition | |
| NVMe disk 1 (M.2_1, RAID 1) | | |
| NVMe disk 2 (M.2_3 / M.2_4, RAID 1) | | |
| PSU | Seasonic PRIME PX-2200 | |
| IPMI card (board revision, e.g. R1.04) | ASUS IPMI Expansion Card-SI | |

## Network

| Port | Permanent MAC | Name | Address |
|---|---|---|---|
| 10 GbE (AQC113) | | `lan10g` | bond0: |
| 2.5 GbE (I226-V) | | `lan2g5` | (bond member) |
| IPMI card LAN | | | |
| IPMI card USB link | | `bmc-usb` | 169.254.0.18/16, card at 169.254.0.17 |

## Access

| Item | Value |
|---|---|
| BMC URL | |
| BMC accounts | `Administrator`: password entry ___; `admin`: password entry ___ / disabled |
| OS admin user | , password / SSH key entry ___ |

## Versions

| Item | Version |
|---|---|
| BIOS | |
| BMC firmware | |
| OS, kernel | |
| NVIDIA driver | |
| Docker, NVIDIA Container Toolkit | |
| fan2go | |

## Fan channels

Standard: GPU fan A on channel 4, GPU fan B on channel 6
([04](04-provisioning.md) Phase 6, "Check the fan channels").

| Fan | Header | hwmon channel (unplug test, expected) |
|---|---|---|
| GPU fan A | | (4) |
| GPU fan B | | (6) |

## Acceptance

| Check | Date | Result |
|---|---|---|
| Memory test | | |
| GPU thermal (10 min, 2x 500 W) | | max temp ___ C, fan duty ___ % |
| GPU stability (1 h) | | |
| Disks | | |
| Power loss, BMC power cycle | | |
| Network failover | | |
| Host checks ([05](05-acceptance.md) section 2) | | |
| Inventory file attached | | `/root/inventory-YYYYMMDD.txt` |
