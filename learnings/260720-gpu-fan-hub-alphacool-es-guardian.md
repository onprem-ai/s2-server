# GPU Fans for Passive Blackwell Cards, and the Alphacool ES Guardian Hub

**Date:** 2026-07-20
**Hardware:** ASUS board with nct6799 Super I/O, 2x RTX PRO 6000 Blackwell Server
Edition (passive, no fans of their own), 2x Arctic S12038-8K fans blowing into the GPUs,
Alphacool ES Guardian 4-port fan hub

## Summary

- **What happened:** the GPU fans did not speed up under GPU load. The Alphacool ES
  Guardian hub never passed a tach or PWM signal to the board.
- **Cause:** the board's fan curves follow only CPU and board temperatures, never the
  GPU. Passive server-edition GPUs have no fans of their own and throttle or shut down
  without chassis airflow.
- **Fix:** hub retired. Each fan is powered from the PSU through a SATA adapter; the
  board header carries only PWM and tach. [fan2go](https://github.com/markusressel/fan2go)
  in the OS drives the fans from GPU temperature.

## Mapping fans to sysfs channels

The nct6799 channel numbers do not match the CHA_FANn labels on the board 1:1. Map them
by test:

- Disconnect one fan and see which `fanN_input` in sysfs drops to 0.
- Put a brief all-core load on the CPU and see which fans follow CPU temperature:

```bash
for i in $(seq $(nproc)); do (while :; do :; done) & done
# watch the fan inputs, then stop the load:
kill $(jobs -p)
```

Temperature sources: `k10temp` (CPU `Tctl`), `asusec` (CPU, CPU package, motherboard),
GPUs through `nvidia-smi` / NVML. An `asusec` T_Sensor reading of -62 C means no sensor
is connected.

## Arctic S12038-8K specs (Arctic spec sheet)

| Property | Value |
|---|---|
| Size / speed | 120x120x38 mm, 800-8000 RPM, PWM (25 kHz) |
| Current nominal | 2.2 A at 12 V (26 W) per fan |
| Current maximum | 3.2 A per fan (Arctic: the source must supply at least 3.2 A) |
| Airflow / pressure | 220 CFM / 37 mmH2O |
| Bearing | dual ball bearing, rated for continuous operation |

Never power high-current server fans like these from a board fan header (about 1 A).
The header's fuse trips and the fan stops and starts every few seconds. During
debugging a fan briefly powered from a header pulsed on and off about every 2 s at
100% duty. Power the fans from the PSU through a SATA adapter; use the header only for
PWM and tach.

## Why the GPU fans matter

The RTX PRO 6000 Blackwell Server Edition has no fans. All its cooling comes from
chassis airflow, here the two Arctic fans. The board's fan curves see only CPU and
board temperatures. Without an OS fan controller the GPU fans never speed up under
GPU load. With the chassis closed and all fans running, the GPUs ran at 62-65 C under
sustained single-stream inference.

## Alphacool ES Guardian 4-Port Powerfan Hub

Specs (Alphacool product page):

| Property | Value |
|---|---|
| Power input | 2x 4-pin Molex from the PSU (not from the fan header) |
| Continuous / max current | 12 A / 16 A at 12 V |
| Fan ports | 4x 4-pin PWM |
| Mainboard link | 1x 4-pin PWM cable (400 mm): receives PWM duty, returns one RPM signal |
| Monitoring config | 4-way DIP switch: monitoring on/off per port |
| Extras | Speaker port (alarm on fan failure), 2x CAN bus (needs Alphacool CAN controller), status LED per port |
| Size | 120 x 38 x 18 mm |

Power rules:

- Alphacool requires the second power connector for fans over 1.5 A each. With these
  fans (4.4 A nominal, 6.4 A peak for two) both Molex inputs must be fed.
- Feed both inputs from the same PSU (Y-splitter or a second peripheral cable). The
  12 V inputs are joined on the hub. Feeding them from two PSUs back-feeds the second
  PSU and trips its over-current protection (observed: the PSU shut down, no damage).

Tach behaviour (documented by Alphacool):

- The hub sends the board the RPM of the first active (monitored) port.
- If any monitored fan fails, the hub sends no RPM signal (0 RPM). So 0 RPM on the hub
  header is an alarm for all monitored fans.
- DIP switches must be on exactly for the populated ports. A monitored but empty port
  counts as a failed fan and suppresses the tach signal.

If the header reads 0 RPM although the fans spin, check in this order:

1. DIP switches on for empty ports (all-on default with 2 fans on 4 ports).
2. All DIP switches off: nothing is forwarded.
3. Port numbering: put fans in ports 1 and 2, DIP 1 and 2 on.
4. Only then suspect the PWM cable or the header-to-channel mapping.

PWM path: the hub passes the header's PWM duty to all four ports, so one board channel
controls all fans on the hub. The fans are PSU-powered and spin whatever the board does.

## Resolution: hub retired, fan2go controls the GPU fans

The hub gave no tach and no PWM response through its board link in any DIP or port
combination. No community reports exist for this product. Final wiring:

- Each Arctic fan is powered from the PSU through its own SATA adapter.
- Each fan's tach and PWM go to a board chassis header (signal only). This works fine.
- fan2go runs as a systemd service. It drives both fans from the highest of the two
  GPU temperatures and a CPU assist. It reads the GPUs natively through NVML, with no
  wrapper scripts. On first start it calibrates each fan's PWM-to-RPM curve, then holds
  manual PWM mode; the board firmware does not fight it.

Closed loop under a dual-GPU burn: 36 C idle → 20% (2.7k RPM); 55 C → 40%;
64 C → 65%; 69 C → 78% (6.5k RPM); the fans ramp back down on cooldown. Before, the
fans never responded to GPU load.

## Thermal validation

Power limit 500 W per card (`nvidia-smi -pl 500`, from 600 W stock). This setting is
lost on reboot unless a boot service applies it.

- **Chassis open, 2x 500 W for 10 min:** plateau 76-78 C from minute 2, fans at 92-94%
  (7.2k / 6.5k RPM), instant recovery when the load stops. Margin to 85 C: 7-9 C. At
  600 W the fans would saturate; the 500 W cap and this fan curve go together.
- **Thermal cycling (3x, heat to 73 C, coast to 49 C):** heat-up 20 / 35 / 40 s
  (longer as the heatsinks warm-soak), cool-down steady at 50-56 s.
- **Chassis closed, front and rear chassis fans connected (firmware curves):** plateau
  77-78 C at 94% fan duty, within 1 C of the open-chassis result.
- Fan current at 94% duty (about 91% of max RPM, cube law): about 1.7 A / 20 W per fan.
  Fine on a SATA line, about 3x a board header rating.

## CPU temperature during a GPU burn

During the GPU burn the CPU reaches 84 to 85 C (idle about 60 C). This comes from the
burn's own submit threads, not from GPU heat. Test with the chassis closed, sampling
every 5 s:

- **CPU load only (2 cores spinning, GPUs idle, 3 min):** `Tctl` 58 → 89 C, socket
  49 → 79 C.
- **GPU burn 2x 500 W, 6 min:** `Tctl` jumped 60 → 84 C within 26 s, before the GPUs
  were hot, then stayed at 84 C for 6 min while the GPUs rose another 9 C. No
  correlation with GPU temperature. Same signature as the CPU-only test: two busy
  submit threads.
- Motherboard sensor: +2 C over 6 min of 1 kW GPU load. The ducted GPU airflow keeps
  GPU heat away from the CPU.

This is inside the Ryzen limit (about 95 C) and is normal Ryzen boost behaviour on one
or two busy cores. The firmware CPU fan curve stayed at about 690 RPM even at
`Tctl` 89 C; set a steeper CPU fan curve in the BIOS or hand the CPU fan to fan2go.

## Prevention

- Power server fans from the PSU, never from a board header.
- Run an OS fan controller (fan2go) that reads GPU temperature.
- Alert if a GPU fan's tach reads 0 while its PWM is above 0. fan2go also logs an
  error when RPM does not match the expected value.
- If the hub is reused: feed both Molex inputs from the same PSU.
