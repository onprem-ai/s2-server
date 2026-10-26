# Rear fans: Arctic P8 Max, black (2x)

80 mm PWM fans in the chassis's two rear positions, behind the CPU, blowing out.
[Product page](https://www.arctic.de/en/P8-Max/ACFAN00286A). Downloaded 2026-10-24 from
Arctic.

| File | What | Source |
|---|---|---|
| [Arctic_P8_Max_spec_sheet_EN.pdf](Arctic_P8_Max_spec_sheet_EN.pdf) | Specification sheet | [arctic.de](https://www.arctic.de/media/3f/04/7e/1689685872/Spec_Sheet_P8_Max_EN.pdf) |

## Key facts for the S2

| Item | Value | Where it matters |
|---|---|---|
| Size | 80 x 80 x 25 mm | Chassis rear positions ([chassis](../chassis/)) |
| Speed | 500 to 5000 rpm by PWM; stops below 5 % PWM | A firmware curve with a floor above 5 %, so the fans never stop |
| Airflow, static pressure | 40 cfm, 5.3 mmH2O | |
| Current | 0.19 A at 12 V | Board header (1 A) powers it directly, unlike the GPU fans |
| Connector | 4-pin PWM, 400 mm cable | Two free chassis fan headers, not the two kept for the GPU fans (channels 4 and 6) |
| SKU | ACFAN00286A (EAN 4895213704090) | [01 BOM](../../01-bom.md) item 18 |
