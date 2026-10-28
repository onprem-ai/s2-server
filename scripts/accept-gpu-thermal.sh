#!/bin/bash
# GPU load test (05 Acceptance, "GPU thermal"): build gpu-burn for Blackwell (sm_120), 10 min on both GPUs,
# log temperatures, power, throttle reasons and GPU fan RPM every 10 s.
set -euo pipefail
dnf install -y -q git >/dev/null
MIN=${1:-10}
rm -rf /tmp/gpu-burn && git clone -q https://github.com/wilicc/gpu-burn /tmp/gpu-burn
cd /tmp/gpu-burn && git log -1 --format='gpu-burn commit %H'
docker build -q --build-arg CUDA_VERSION=12.8.1 --build-arg IMAGE_DISTRO=ubuntu24.04 --build-arg COMPUTE=120 -t gpu-burn:local .
H=$(grep -l '^nct67' /sys/class/hwmon/hwmon*/name | xargs dirname)
LOG=${LOGDIR:-$(getent passwd "${SUDO_USER:-root}" | cut -d: -f6)}/gpu-burn-$(date +%Y%m%d-%H%M).csv
echo "time,gpu,temp_c,power_w,clock_mhz,throttle,fan4_rpm,fan6_rpm,pwm4" > "$LOG"
( while true; do
    f4=$(cat $H/fan4_input); f6=$(cat $H/fan6_input); p4=$(cat $H/pwm4)
    nvidia-smi --query-gpu=index,temperature.gpu,power.draw,clocks.sm,clocks_event_reasons.active --format=csv,noheader,nounits \
      | sed "s/^/$(date +%T),/; s/$/,$f4,$f6,$p4/" >> "$LOG"
    sleep 10
  done ) & MON=$!
trap 'kill $MON 2>/dev/null' EXIT
BURN=$(docker run --rm --gpus all --entrypoint /app/gpu_burn gpu-burn:local -tc $((MIN*60)) 2>&1 | grep -vE '^\s*[0-9.]+%  proc' | tail -15); echo "$BURN"
echo "=== cooldown 90 s"; sleep 90
kill $MON
echo "=== max temp per GPU:"; awk -F, 'NR>1{if($3>m[$2])m[$2]=$3} END{for(g in m)print "GPU"g": "m[g]" C"}' "$LOG"
MAX=$(awk -F, 'NR>1&&$3+0>m{m=$3+0} END{print m+0}' "$LOG")
# Thermal slowdown bits of clocks_event_reasons: 0x20 SW thermal, 0x40 HW thermal, 0x80 HW power brake.
THR=$(awk -F, 'NR>1{v=strtonum($6); if(and(v,0xE0))n++} END{print n+0}' "$LOG")
XID=$(journalctl -k -b --no-pager | grep -ciE 'NVRM: Xid|AER:' || true)
OKS=$(echo "$BURN" | grep -c ': OK' || true)
echo "=== burn: $OKS of $(nvidia-smi -L | grep -c ^GPU) GPUs OK; max $MAX C (limit 80); thermal slowdown samples $THR; Xid/AER $XID"
nvidia-smi -L
echo "=== DONE log: $LOG"
if [ "$OKS" = "$(nvidia-smi -L | grep -c ^GPU)" ] && [ "$MAX" -lt 80 ] && [ "$THR" = 0 ] && [ "$XID" = 0 ]; then
  echo "RESULT gpu-thermal: PASS"; exit 0
else
  echo "RESULT gpu-thermal: FAIL (needs: every GPU OK, below 80 C, no thermal slowdown, no Xid/AER)"; exit 1
fi
