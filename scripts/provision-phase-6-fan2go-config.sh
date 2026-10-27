#!/bin/bash
# s2-server 04 Phase 6: fan2go config and service. Check the platform and device names
# against `fan2go detect` first (S2 defaults below); fan channels 4 and 6 per the unplug test.
set -euo pipefail
NCT=${NCT:-nct6799-isa-0290}; CPU=${CPU:-k10temp-pci-00c3}
GPU0=${GPU0:-nvidia-10DE2BB5-0100}; GPU1=${GPU1:-nvidia-10DE2BB5-0300}
cat > /etc/fan2go/fan2go.yaml <<X
# GPU airflow fans for passive GPUs. Fans are PSU-powered; headers carry only PWM and tach.
dbPath: "/var/lib/fan2go/fan2go.db"
fanController:
  adjustmentTickRate: 1000ms
fans:
  - id: gpu_fan_a
    hwmon:
      platform: ${NCT}
      rpmChannel: 4
      pwmChannel: 4
    neverStop: true
    curve: gpu_airflow_curve
    controlMode:
      onExit:
        mode: pwm
        speed: 255
  - id: gpu_fan_b
    hwmon:
      platform: ${NCT}
      rpmChannel: 6
      pwmChannel: 6
    neverStop: true
    curve: gpu_airflow_curve
    controlMode:
      onExit:
        mode: pwm
        speed: 255
sensors:
  - id: gpu0_temp
    nvidia:
      device: ${GPU0}
      index: 1
  - id: gpu1_temp
    nvidia:
      device: ${GPU1}
      index: 1
  - id: cpu_temp
    hwmon:
      platform: ${CPU}
      index: 1
curves:
  - id: gpu_airflow_curve
    function:
      type: maximum
      curves: [gpu0_curve, gpu1_curve, cpu_assist_curve]
  - id: gpu0_curve
    linear:
      sensor: gpu0_temp
      steps:
        - 40: 30%
        - 55: 60%
        - 65: 85%
        - 72: 100%
  - id: gpu1_curve
    linear:
      sensor: gpu1_temp
      steps:
        - 40: 30%
        - 55: 60%
        - 65: 85%
        - 72: 100%
  - id: cpu_assist_curve
    linear:
      sensor: cpu_temp
      steps:
        - 60: 20%
        - 75: 40%
logging:
  level: info
X
cat > /etc/systemd/system/fan2go.service <<'X'
[Unit]
Description=fan2go: GPU-temperature-driven fan control
Documentation=https://github.com/markusressel/fan2go
After=nvidia-persistenced.service systemd-modules-load.service
Wants=nvidia-persistenced.service

[Service]
Type=simple
ExecStart=/usr/local/bin/fan2go --no-color --no-style
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
X
systemctl daemon-reload
systemctl enable --now fan2go
echo "=== fan2go started; first start measures each fan (about a minute)"
sleep 90
systemctl is-active fan2go
journalctl -u fan2go --no-pager -n 15
H=$(grep -l '^nct67' /sys/class/hwmon/hwmon*/name | xargs dirname)
nvidia-smi --query-gpu=index,temperature.gpu --format=csv,noheader
for c in 4 6; do echo "fan$c $(cat $H/fan${c}_input) rpm pwm $(cat $H/pwm$c)"; done
echo "=== DONE"
