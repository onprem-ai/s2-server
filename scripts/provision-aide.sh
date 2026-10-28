#!/bin/bash
# 04 Phase 7, "File integrity (AIDE)": AIDE watches an explicit list of system paths only
# (include list, nothing else: a new data directory never needs a change here); a nightly
# check; one report per night under /var/log/aide/, the last 3 years (1095 days) kept.
# Safe to run again: a changed watch list makes a new baseline, otherwise it is kept.
set -euo pipefail
KEEP_DAYS=${KEEP_DAYS:-1095}
dnf install -y aide

# Our own configuration replaces the distribution's: only these system paths are watched.
# Data (model weights, Docker, caches, logs, homes) is never listed, wherever it lives.
[ -f /etc/aide.conf.dist ] || cp -a /etc/aide.conf /etc/aide.conf.dist
NEWCONF=$(mktemp)
cat > "$NEWCONF" <<'X'
# onprem.ai S2: AIDE watches system files only (s2-server 04 Phase 7, AIDE).
# Include list: anything not listed here is not watched. Keep data out of these paths.
database_in=file:/var/lib/aide/aide.db.gz
database_out=file:/var/lib/aide/aide.db.new.gz
gzip_dbout=yes
log_level=warning
report_level=changed_attributes
report_url=stdout

SYS = p+i+n+u+g+s+m+c+acl+selinux+xattrs+sha512
DIR = p+i+n+u+g+acl+selinux+xattrs

/boot           SYS
/etc            SYS
/usr            SYS
/opt            SYS
/root/\.ssh     SYS
/root/\.bashrc$ SYS
/root/\.bash_profile$ SYS
/var/spool/cron SYS
/var/lib/aide$  DIR

# Inside the watched paths: files that change by design.
!/etc/mtab$
!/etc/.*~$
!/etc/adjtime$
!/etc/aide\.conf\.dist$
!/boot/grub2/grubenv$
!/usr/src/kernels/.*/\.cache
X
CHANGED=1; cmp -s "$NEWCONF" /etc/aide.conf && CHANGED=0
install -m 0600 "$NEWCONF" /etc/aide.conf; rm -f "$NEWCONF"
aide --config-check

# Baseline: once. A changed system after a planned update gets a new baseline with
# `aide-accept` (below), never automatically.
if [ ! -f /var/lib/aide/aide.db.gz ] || [ "$CHANGED" = 1 ]; then
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
