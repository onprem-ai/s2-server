#!/bin/bash
# 05 Acceptance, attended part: disk health + a short run of every long test.
set -uo pipefail
OUT=${LOGDIR:-$(getent passwd "${SUDO_USER:-root}" | cut -d: -f6)}/accept-short-$(date +%Y%m%d-%H%M).log
exec > >(tee "$OUT") 2>&1
ok=0; fail=0
res() { if [ "$1" = 0 ]; then echo "RESULT $2: PASS"; ok=$((ok+1)); else echo "RESULT $2: FAIL"; fail=$((fail+1)); fi; }
echo "=== $(hostname) $(date '+%F %T')"
dnf install -y -q fio >/dev/null

echo; echo "=== Disk health (smartctl)"
r=0
for d in /dev/nvme0 /dev/nvme1; do
  smartctl -H -A "$d" | grep -E "overall-health|Critical Warning|Media and Data Integrity Errors|Percentage Used|Temperature:|Power On Hours|Unsafe Shutdowns"
  smartctl -H "$d" | grep -q PASSED || r=1
  [ "$(smartctl -A "$d" | awk -F: '/Media and Data Integrity Errors/{gsub(/ /,"",$2);print $2}')" = 0 ] || r=1
done
cat /proc/mdstat | head -3
res $r "disk health"

echo; echo "=== Short memtester 1G"
memtester 1G 1 2>&1 | tr '\r\b' '\n\n' | grep -E "ok|FAILURE|Done" | sort -u | tail -5
res "${PIPESTATUS[0]}" "memtester short"

echo; echo "=== Short fio 1G (write then verify-read)"
mkdir -p /var/tmp/fio && fio --name=short --directory=/var/tmp/fio --size=1G --bs=1M --rw=write \
  --ioengine=libaio --direct=1 --iodepth=16 --verify=crc32c --do_verify=1 --group_reporting 2>&1 \
  | grep -E "WRITE:|READ:|err=|verify"
res "${PIPESTATUS[0]}" "fio short"; rm -rf /var/tmp/fio

echo; echo "=== Short gpu-burn 60 s"
G=$(docker run --rm --gpus all --entrypoint /app/gpu_burn gpu-burn:local -tc 60 2>&1 | grep -E "GPU [0-9]: (OK|FAULTY)"); echo "$G"
[ "$(echo "$G" | grep -c OK)" = 2 ] && ! echo "$G" | grep -q FAULTY; res $? "gpu-burn short"

echo; echo "=== GPU errors in kernel log"
n=$(dmesg | grep -ciE 'NVRM: Xid|AER:'); echo "Xid/AER lines: $n"; res $([ "$n" = 0 ] && echo 0 || echo 1) "no Xid/AER"

echo; echo "=== SUMMARY: $ok passed, $fail failed. Log: $OUT"
