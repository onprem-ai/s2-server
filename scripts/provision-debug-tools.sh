#!/bin/bash
# 04 Phase 1, "Admin tools": the diagnosis tools, and atop recording the whole machine
# every 30 s (/var/log/atop, kept 28 days): after a hang or crash the minutes before it are
# on disk (learnings/260925-host-test-memory-exhaustion-thrash-crash.md). Safe to run again.
set -euo pipefail
dnf install -y -q epel-release >/dev/null
dnf install -y atop sysstat htop nvtop iotop-c tmux lsof strace tcpdump pciutils ethtool \
  smartmontools nvme-cli bind-utils ipmitool

# atop: 30 s samples, 28 days of daily files, readable by every user (no root needed to read).
# Config and unit names differ between atop versions: find them instead of assuming.
CONF=$(ls /etc/sysconfig/atop /etc/default/atop 2>/dev/null | head -1 || true)
if [ -n "$CONF" ]; then
  grep -q '^LOGINTERVAL=' "$CONF" && sed -i 's/^LOGINTERVAL=.*/LOGINTERVAL=30/' "$CONF" || echo 'LOGINTERVAL=30' >> "$CONF"
  grep -q '^LOGGENERATIONS=' "$CONF" && sed -i 's/^LOGGENERATIONS=.*/LOGGENERATIONS=28/' "$CONF" || echo 'LOGGENERATIONS=28' >> "$CONF"
  echo "atop config $CONF: $(grep -E '^(LOGINTERVAL|LOGGENERATIONS)=' "$CONF" | paste -sd' ')"
else
  echo "STOP: no atop configuration file found (/etc/sysconfig/atop, /etc/default/atop)"; exit 1
fi
for u in atop.service atop-rotate.timer sysstat.service sysstat-collect.timer sysstat-summary.timer; do
  if systemctl list-unit-files "$u" --no-legend | grep -q .; then systemctl enable --now "$u"; else echo "note: unit $u not in this version"; fi
done
systemctl restart atop
sleep 3
for u in atop sysstat; do echo "$u: $(systemctl is-active $u)"; done
[ "$(systemctl is-active atop)" = active ] || { echo "STOP: atop is not running"; exit 1; }
ls -l /var/log/atop/ | tail -2
echo "=== DONE"
