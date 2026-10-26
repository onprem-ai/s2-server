# CPU cooler: Thermalright Peerless Assassin 120 Mini, black

Dual-tower air cooler with one 120 mm fan between the towers.
[Product page](https://www.thermalright.com/product/peerless-assassin-120-mini-black/).
Downloaded 2026-10-24 from Thermalright.

| File | What | Source |
|---|---|---|
| [Thermalright_Peerless_Assassin_120_Mini_Black_manual.pdf](Thermalright_Peerless_Assassin_120_Mini_Black_manual.pdf) | Installation manual (AM5 mounting) | [thermalright.com](https://download.thermalright.com/manuals/PEERLESSASSASSIN120MINIBLACK.pdf) |

## Key facts for the S2

| Item | Value | Where it matters |
|---|---|---|
| Sockets | AM4, AM5; Intel LGA115x/1200/1700/1851/2011/2066 | Ryzen 9 9900X, AM5 |
| Heatsink | 125 x 110 x 135 mm (L x W x H), 700 g; 6 heat pipes of 6 mm, nickel-plated copper base | Chassis cooler limit 137 mm ([chassis](../chassis/)) |
| Fan | Thermalright TL-D12B, 120 x 120 x 25 mm, up to 1500 rpm, 0.20 A, 4-pin PWM, fluid dynamic bearing | On CPU_FAN (`fan2` in Linux), firmware curve |
| Airflow direction | Towards the rear of the chassis | The rear fans take the air out ([rear-fans](../rear-fans/)) |

During a GPU burn the CPU reaches 84 to 85 C (Ryzen limit 95 C), from the burn's own
CPU threads; set a steeper CPU fan curve in the BIOS
([04](../../04-provisioning.md) Phase 6).
