#!/bin/bash
# 04 Phase 7, "File integrity (AIDE)": AIDE on the distribution's default rules (system
# files), minus the data that changes all the time; a nightly check; one report per night
# under /var/log/aide/, the last 90 days kept. Safe to run again (keeps the baseline).
set -euo pipefail
KEEP_DAYS=${KEEP_DAYS:-90}
dnf install -y aide

# Exclusions: data that changes by design. Not /etc, /usr, /boot: those are the point.
# Appended to /etc/aide.conf in one marked block (works with every AIDE version; replaced on re-run).
sed -i '/^# BEGIN onprem-ai/,/^# END onprem-ai/d' /etc/aide.conf
cat >> /etc/aide.conf <<'X'
# BEGIN onprem-ai: data that changes by design (s2-server 04 Phase 7, AIDE)
!/var/lib/onprem-ai/
!/var/lib/docker/
!/var/lib/containerd/
!/srv/docker/
!/var/lib/fan2go/
!/var/cache/
!/var/tmp/
!/var/lib/dnf/
!/var/lib/rpm/
!/var/lib/dkms/
!/var/lib/nvidia-persistenced/
!/home/
!/root/
# END onprem-ai
X
aide --config-check

# Baseline: once. A changed system after a planned update gets a new baseline with
# `aide-accept` (below), never automatically.
if [ ! -f /var/lib/aide/aide.db.gz ]; then
  echo "=== creating the baseline (a few minutes)"
  aide --init >/dev/null
  mv /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz
fi

install -d -m 0700 /var/log/aide
cat > /usr/local/sbin/aide-nightly <<X
#!/bin/bash
# Nightly AIDE check: one report per day in /var/log/aide/, older than ${KEEP_DAYS} days removed.
R=/var/log/aide/aide-\$(date +%F).log
/usr/sbin/aide --check > "\$R" 2>&1; rc=\$?
chmod 0600 "\$R"
find /var/log/aide -name 'aide-*.log' -mtime +${KEEP_DAYS} -delete
# Exit 0: no change. Bits 1/2/4: added/removed/changed files. 8 and higher: AIDE error.
[ \$rc -eq 0 ] && logger -t aide "no changes" || logger -p auth.warning -t aide "changes or error (exit \$rc): \$R"
exit 0
X
cat > /usr/local/sbin/aide-accept <<'X'
#!/bin/bash
# After a planned change (update, configuration), read the latest report, then accept the
# current state as the new baseline. The old baseline is kept as aide.db.gz.prev.
set -euo pipefail
/usr/sbin/aide --update || [ $? -lt 8 ]
mv /var/lib/aide/aide.db.gz /var/lib/aide/aide.db.gz.prev
mv /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz
echo "new AIDE baseline accepted $(date '+%F %T')" | logger -t aide
X
chmod 0700 /usr/local/sbin/aide-nightly /usr/local/sbin/aide-accept
restorecon -v /usr/local/sbin/aide-nightly /usr/local/sbin/aide-accept 2>/dev/null || true

cat > /etc/systemd/system/aide-check.service <<'X'
[Unit]
Description=AIDE file integrity check (report in /var/log/aide)
[Service]
Type=oneshot
Nice=19
IOSchedulingClass=idle
ExecStart=/usr/local/sbin/aide-nightly
X
cat > /etc/systemd/system/aide-check.timer <<'X'
[Unit]
Description=Nightly AIDE file integrity check
[Timer]
OnCalendar=*-*-* 04:30:00
RandomizedDelaySec=30m
Persistent=true
[Install]
WantedBy=timers.target
X
systemctl daemon-reload
systemctl enable --now aide-check.timer
systemctl list-timers aide-check.timer --no-pager | head -2

echo "=== first check now"
/usr/local/sbin/aide-nightly
ls -l /var/log/aide/
grep -E "^(AIDE found|Summary|  Total|  Added|  Removed|  Changed)" /var/log/aide/aide-$(date +%F).log || head -5 /var/log/aide/aide-$(date +%F).log
echo "=== DONE"
