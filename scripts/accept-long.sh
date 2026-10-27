#!/bin/bash
# 05 Acceptance, unattended part: full memory pass, fio full job, gpu-burn 1 h. Start it in tmux and leave.
set -uo pipefail
OUT=${LOGDIR:-$(getent passwd "${SUDO_USER:-root}" | cut -d: -f6)}/accept-long-$(date +%Y%m%d-%H%M).log
exec > >(tee "$OUT") 2>&1
ok=0; fail=0
res() { if [ "$1" = 0 ]; then echo "RESULT $2: PASS $(date '+%F %T')"; ok=$((ok+1)); else echo "RESULT $2: FAIL $(date '+%F %T')"; fail=$((fail+1)); fi; }
echo "=== $(hostname) start $(date '+%F %T')"

echo; echo "=== Memory: memtester, one full pass"
SIZE=$(( $(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo) - 4096 ))M; echo "size $SIZE"
memtester "$SIZE" 1 2>&1 | tr '\r\b' '\n\n' | grep -E "ok|FAILURE|Done|Loop" | sort -u | tail -25
res "${PIPESTATUS[0]}" "memtester full"

echo; echo "=== Disks: fio 50G write + verify, then random read"
mkdir -p /var/tmp/fio
fio --name=seq --directory=/var/tmp/fio --size=50G --bs=1M --rw=write --ioengine=libaio --direct=1 \
  --iodepth=32 --verify=crc32c --do_verify=1 --group_reporting 2>&1 | grep -E "WRITE:|READ:|err="
r1=${PIPESTATUS[0]}
fio --name=rand --directory=/var/tmp/fio --size=50G --bs=4k --rw=randread --ioengine=libaio --direct=1 \
  --iodepth=64 --numjobs=4 --runtime=300 --time_based --group_reporting 2>&1 | grep -E "READ:|err=|iops"
r2=${PIPESTATUS[0]}; rm -rf /var/tmp/fio
res $(( r1 + r2 )) "fio full"
for d in /dev/nvme0 /dev/nvme1; do smartctl -A $d | grep -E "Media and Data Integrity Errors|Temperature:"; done

echo; echo "=== GPU stability: gpu-burn 1 h"
H=$(grep -l '^nct67' /sys/class/hwmon/hwmon*/name | xargs dirname)
( while true; do echo "$(date +%T) $(nvidia-smi --query-gpu=temperature.gpu,power.draw --format=csv,noheader | tr '\n' ' ') fans $(cat $H/fan4_input)/$(cat $H/fan6_input)"; sleep 60; done ) & MON=$!
G=$(docker run --rm --gpus all --entrypoint /app/gpu_burn gpu-burn:local -tc 3600 2>&1 | grep -E "GPU [0-9]: (OK|FAULTY)"); kill $MON
echo "$G"
[ "$(echo "$G" | grep -c OK)" = 2 ] && ! echo "$G" | grep -q FAULTY; res $? "gpu-burn 1 h"
nvidia-smi -L
n=$(dmesg | grep -ciE 'NVRM: Xid|AER:'); echo "Xid/AER lines: $n"; res $([ "$n" = 0 ] && echo 0 || echo 1) "no Xid/AER"

echo; echo "=== SUMMARY $(date '+%F %T'): $ok passed, $fail failed. Log: $OUT"
