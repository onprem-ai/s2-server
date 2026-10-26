# GPU fan duct: custom 3D-printed part

A custom duct in front of the two passive GPUs. It holds both 120 mm GPU fans
(Arctic S12038-8K, [BOM](../../01-bom.md) item 9) **in series**: one directly behind
the other, both blowing the same way, front to back. Their static pressure adds up and
pushes enough air through the dense fin stacks of the passive GPUs. The one air stream
feeds **both GPUs at the same time**; there is no fan per GPU. Assembly:
[02](../../02-assembly.md), steps 12 and 13.

What follows from the series layout:

- Both fans must blow in the same direction, towards the GPUs. One turned the other
  way works against the other and the GPUs get almost no air.
- Both fans run on the same curve (fan2go, [04](../../04-provisioning.md) Phase 6), set
  by the hotter GPU.
- One fan alone still moves air, but with far less pressure than the pair. A failed
  fan is replaced at once ([06](../../06-operations.md)), not at the next visit.

| File | What |
|---|---|
| TODO: `gpu-fan-duct.stl` | The part to print (to be added) |
| [Prusament_PETG_V0_technical_datasheet_EN.pdf](Prusament_PETG_V0_technical_datasheet_EN.pdf) | Filament technical datasheet, v1.0 (2023-08-01), from [prusament.com](https://prusament.com/wp-content/uploads/2023/07/PETG_V0_ENG.pdf) |
| [Prusament_PETG_V0_safety_datasheet_EN.pdf](Prusament_PETG_V0_safety_datasheet_EN.pdf) | Filament safety data sheet (REACH), v1.0 (2023-07-25), from [prusament.com](https://prusament.com/wp-content/uploads/2023/07/SDS_Prusament_PETG_V0_EN.pdf) |
| [Prusament_PETG_V0_UL_certification_E527425.pdf](Prusament_PETG_V0_UL_certification_E527425.pdf) | UL certification ("Blue Card") E527425, report date 2023-08-01; live record at [UL Product iQ](https://iq.ul.com/ul/cert.aspx?ULID=104636411) |

## Material: fire-resistant, certified filament

The duct sits inside a 2 kW machine, next to the GPUs' 12V-2x6 power connectors, and
runs unattended. Print it in a self-extinguishing filament with a UL flammability
certification, not in ordinary PLA or PETG.

Recommended: **Prusament PETG V0** by Prusa Polymers (Prague, Czech Republic),
[product page](https://prusament.com/materials/prusament-petg-v0/). A flame-retardant
PETG, certified by UL as **UL94 V-0** (self-extinguishing) under IEC 60695-11-10, UL
file E527425. It prints like ordinary PETG on any printer with a heated bed.

| Item | Value | Source |
|---|---|---|
| Flame class | V-0, at 0.75 mm and at 3.0 mm wall thickness | UL E527425 |
| Certified colours | Natural (NC) and black (BK) | UL E527425 |
| Relative temperature index (RTI) | 75 °C (electrical, impact, strength) | UL E527425 |
| Heat deflection temperature | 68 °C at 0.45 MPa, 74 °C at 1.80 MPa | Technical datasheet |
| Diameter | 1.75 ± 0.02 mm | Technical datasheet |
| Nozzle | 230 ± 10 °C | Technical datasheet |
| Bed | 80 ± 10 °C; satin or textured (powder-coated) sheet; smooth PEI only with a glue stick | Technical datasheet |
| Part cooling fan | 50 % | Technical datasheet |
| Print speed | Up to 200 mm/s | Technical datasheet |
| Storage | Dry; more hygroscopic than ordinary PETG. Dry before use if it was not stored dry: 6 hours at 55 °C | Prusa product description |

What the certificate covers, and how to keep the part within it:

- The V-0 rating holds for samples printed with the certified parameters: 0.4 mm
  nozzle, 0.2 mm layers, 100 % solid (no air gap), raster 45/-45, 55 to 200 mm/s, on
  the Prusa printers named in the certificate (MK3S+, MK4, MK4S, XL, Core One) with
  the "Balanced" or default preset. Other settings or printers can give a different
  result: print the duct as close to these as the part allows.
- Keep every wall at least 0.75 mm thick, the thinnest thickness UL tested.
- Use one of the two certified colours, natural or black.
- The duct takes in chassis air at room temperature, well below the 68 °C heat
  deflection temperature. Do not place it in the GPUs' exhaust air.
