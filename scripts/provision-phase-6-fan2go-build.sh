#!/bin/bash
# Build fan2go 0.15.0 from source on Rocky Linux 10 (the release binary needs libsensors.so.5; Rocky has .so.4).
set -euo pipefail
V=0.15.0
dnf install -y --disablerepo=nvidia-container-toolkit golang lm_sensors-devel make git
rm -rf /tmp/fan2go-src && git clone -q --depth 1 --branch "$V" https://github.com/markusressel/fan2go /tmp/fan2go-src
cd /tmp/fan2go-src && git log -1 --format='commit %H'
make build VERSION="$V"
install -m 0755 bin/fan2go /usr/local/bin/fan2go
restorecon -v /usr/local/bin/fan2go 2>/dev/null || true
mkdir -p /etc/fan2go /var/lib/fan2go
echo nct6775 > /etc/modules-load.d/nct6775.conf; modprobe nct6775
ldd /usr/local/bin/fan2go | grep -i sensors
/usr/local/bin/fan2go version
echo "=== fan2go detect"; /usr/local/bin/fan2go detect 2>&1 | tee ${LOGDIR:-$(getent passwd "${SUDO_USER:-root}" | cut -d: -f6)}/fan2go-detect.txt
H=$(grep -l '^nct67' /sys/class/hwmon/hwmon*/name | xargs dirname)
echo "=== fan channels ($H)"; for i in 1 2 3 4 5 6 7; do echo "fan$i $(cat $H/fan${i}_input) rpm"; done
echo "=== DONE"
