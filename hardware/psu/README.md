# PSU: Seasonic PRIME PX-2200 (ATX 3.1)

Downloaded 2026-10-24 from Seasonic. Product page:
[seasonic.com/atx3-prime-px-2200](https://seasonic.com/atx3-prime-px-2200/).

| File | What | Source |
|---|---|---|
| [Seasonic_PRIME_PX-2200_datasheet_v2.pdf](Seasonic_PRIME_PX-2200_datasheet_v2.pdf) | Datasheet, current version (linked from the product page) | [Prime-PX-2200-v2.pdf](https://seasonic.com/wp-content/uploads/2025/03/Prime-PX-2200-v2.pdf) |
| [Seasonic_PRIME_PX-2200_datasheet_v1_2024.pdf](Seasonic_PRIME_PX-2200_datasheet_v1_2024.pdf) | Datasheet, first version (2024). Same as v2 except the load regulation: 0.5 % here, 1 % in v2 | [ATX-3.1-PRIME-PX-2200.pdf](https://seasonic.com/wp-content/uploads/2024/06/ATX-3.1-PRIME-PX-2200.pdf) |
| [Seasonic_PSU_user_manual_multilingual.pdf](Seasonic_PSU_user_manual_multilingual.pdf) | User manual, all Seasonic consumer PSUs (safety, carton contents, troubleshooting) | [Manual-PSU-multilingual.pdf](https://seasonic.com/wp-content/uploads/2024/04/Manual-PSU-multilingual.pdf) |
| [Seasonic_PSU_quick_installation_guide.pdf](Seasonic_PSU_quick_installation_guide.pdf) | Quick installation guide | [QIG-PSU.pdf](https://seasonic.com/wp-content/uploads/2024/09/QIG-PSU.pdf) |
| [Seasonic_native_12V-2x6_cable_datasheet.pdf](Seasonic_native_12V-2x6_cable_datasheet.pdf) | Datasheet of the native 12V-2x6 GPU cable (16 AWG, 700 mm, 600 W) | Seasonic, mirrored at [gzhls.at](https://gzhls.at/blob/ldb/3/d/b/a/336d9fa3b4478c1334cec2b479443edce61e.pdf) |

## Key facts for the S2

From the product page and the datasheet:

| Item | Value | Where it matters |
|---|---|---|
| AC input | 200 to 240 V only, 15 A, 50/60 Hz; C20 inlet, so the cord needs a C19 plug | [01 BOM](../../01-bom.md), power cord and socket |
| +12 V | One rail, 183.3 A (2200 W) | [01 BOM](../../01-bom.md), "Power budget" |
| Modularity | Fully modular: every cable plugs into the PSU | [02 Assembly](../../02-assembly.md), step 7 |
| 12V-2x6, native (12+4 pin to 12+4 pin) | 2 cables, 700 mm | One per GPU |
| 12V-2x6 from 2x 8-pin | 2 cables, 700 mm | Not used on the S2 |
| EPS 12 V (CPU, 8/4 pin) | 3 cables, 700 mm | Two used: one each for the board's CPU_12V_1 and CPU_12V_2 |
| PCIe 8/6 pin | 4 cables, 750 mm | One for the IPMI card's 6-pin |
| SATA | 4 cables with 4 connectors each, 950 mm | GPU fan adapters ([BOM](../../01-bom.md) item 10) |
| Dimensions | 210 x 150 x 86 mm | Longer than a standard ATX PSU (140 mm): check the chassis |
| Warranty | 12 years | |
| Manufacturer part number | `PRIME-PX-2200-ATX30` | [01 BOM](../../01-bom.md) item 11 |

## Hybrid Mode button: off

The small button on the back, next to the power inlet and the I/O switch, is the
**Hybrid Mode** switch for the PSU's own fan.

| Mode | PSU fan |
|---|---|
| Hybrid on | Stops at low load; measured stopped up to about 30 % load (660 W), spinning from 40 % ([Quasarzone review](https://quasarzone.com/bbs/qc_qsz/views/1781465)) |
| Hybrid off ("Normal") | Always runs, about 525 rpm up to half load; above that the same as Hybrid |

**On the S2: Hybrid off.** An idle S2 draws a few hundred watts, enough for Hybrid
mode to stop the fan while the PSU sits in air warmed by the GPUs; noise does not
matter in a rack. Change the mode only with the PSU's I/O switch at `O` (off): Seasonic's
quick installation guide says the change takes effect only then.

The I/O switch itself also resets the PSU: if it does not start, switch it off and on
a few times, about half a second apart (Seasonic user manual, troubleshooting).

Seasonic's rules for the 12V-2x6 cable: both ends fully inserted and click-locked, and
no bending or force on the cable once it is plugged in, least of all next to the
connector.
