#!/bin/bash
# S2 host checks (05-acceptance.md, section 2). Run as root: sudo bash host-checks.sh
# Every line prints PASS, FAIL or INFO with the value it saw. Exit code = number of FAILs.
# Never interactive: package manager calls use -q and --assumeno / -C (cache only).
[ "$(id -u)" = 0 ] || { echo "Run as root (sudo): several checks read root-only state; as another user they give false results."; exit 99; }
fail=0
pass() { printf 'PASS  %-34s %s\n' "$1" "$2"; }
bad()  { printf 'FAIL  %-34s %s\n' "$1" "$2"; fail=$((fail+1)); }
info() { printf 'INFO  %-34s %s\n' "$1" "$2"; }
chk()  { if eval "$2"; then pass "$1" "$3"; else bad "$1" "$3"; fi; }
. /etc/os-release
ROCKY=0; [ "$ID" = rocky ] && ROCKY=1

C=$(cat /proc/cmdline)
for a in pcie_aspm=off pcie_port_pm=off iommu=pt; do chk "kernel parameter $a" '[[ " $C " == *" $a "* ]]' ""; done
chk "nouveau not loaded" '! lsmod | grep -q "^nouveau"' ""

if [ -r /proc/net/bonding/bond0 ]; then
  ACT=$(awk -F': ' '/Currently Active Slave/{print $2}' /proc/net/bonding/bond0)
  chk "bond0 active port" '[ -n "$ACT" ] && [ "$ACT" != None ]' "$ACT"
  awk -F': ' '/Slave Interface/{i=$2} /MII Status/ && i{print i, $2; i=""}' /proc/net/bonding/bond0 | while read -r p s; do
    if [ "$s" = up ]; then pass "bond member $p" "up"; else printf 'FAIL  %-34s %s\n' "bond member $p" "$s (no link: cable or switch port; no redundancy)"; fi
  done
  fail=$((fail + $(awk -F': ' '/Slave Interface/{i=1} /MII Status/ && i{if($2!="up")n++; i=0} END{print n+0}' /proc/net/bonding/bond0)))
else info "bond0" "none (one-port machine)"; fi
DR=$(ip route show default)
chk "default route only on bond0" '[ "$(echo "$DR" | wc -l)" = 1 ] && [[ "$DR" == *" dev bond0 "* ]]' "$DR"

if [ $ROCKY = 1 ]; then
  L=$(dnf -q -C versionlock list 2>/dev/null)
  for p in kernel-core nvidia-driver-cuda kmod-nvidia-open-dkms docker-ce nvidia-container-toolkit; do chk "version lock $p" 'echo "$L" | grep -q "^$p-"' ""; done
  chk "dnf-automatic timer enabled" '[ "$(systemctl is-enabled dnf-automatic.timer 2>/dev/null)" = enabled ]' ""
  A=$(grep -E '^(upgrade_type|apply_updates|reboot) *=' /etc/dnf/automatic.conf | tr -d ' ' | sort | tr '\n' ' ')
  chk "dnf-automatic security only" '[ "$A" = "apply_updates=yes reboot=never upgrade_type=security " ]' "$A"
  chk "SELinux enforcing" '[ "$(getenforce)" = Enforcing ]' "$(getenforce)"
  # Every enabled repository must answer without a prompt (keys imported): what dnf-automatic needs.
  R=$(dnf -q makecache --assumeno 2>&1 | grep -iE 'error|is this ok|signing key' | head -2)
  chk "all repositories readable, keys in" '[ -z "$R" ]' "$R"
else
  chk "kernel held" '[ -n "$(apt-mark showhold | grep linux-image)" ]' ""
  chk "unattended-upgrades on" '[[ "$(apt-config dump APT::Periodic::Unattended-Upgrade)" == *\"1\"* ]]' ""
  chk "GPU stack excluded from unattended" '[ "$(apt-config dump Unattended-Upgrade::Package-Blacklist | grep -c nvidia)" -ge 1 ]' ""
fi

chk "NVIDIA runtime D3 off" 'grep -q "DynamicPowerManagement: 0" /proc/driver/nvidia/params' ""
KV=$(awk '/NVRM version/{for(i=1;i<=NF;i++) if($i ~ /^[0-9]+\.[0-9]+\.[0-9]+$/){print $i; exit}}' /proc/driver/nvidia/version)
UV=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)
chk "driver module = userspace" '[ -n "$KV" ] && [ "$KV" = "$UV" ]' "module $KV, userspace $UV"
NG=$(lspci -d 10de: | grep -cE '3D|VGA'); NS=$(nvidia-smi -L | grep -c '^GPU')
chk "every GPU seen by the driver" '[ "$NG" -ge 1 ] && [ "$NG" = "$NS" ]' "PCI $NG, driver $NS"
nvidia-smi --query-gpu=index,persistence_mode,power.limit,pcie.link.gen.max,pcie.link.width.current --format=csv,noheader,nounits |
while IFS=', ' read -r i pm pl gen w; do
  printf '%s  %-34s %s\n' "$([ "$pm" = Enabled ] && [ "${pl%.*}" = 500 ] && echo PASS || echo FAIL)" "GPU $i persistence, 500 W" "$pm, $pl W"
  info "GPU $i PCIe" "Gen$gen x$w"
done
fail=$((fail + $(nvidia-smi --query-gpu=persistence_mode,power.limit --format=csv,noheader,nounits | awk -F', ' '$1!="Enabled"||int($2)!=500{n++} END{print n+0}')))

for s in nvidia-persistenced nvidia-power-limit docker; do chk "service $s" '[ "$(systemctl is-active $s)" = active ]' "$(systemctl is-active $s)"; done
[ -f /etc/fan2go/fan2go.yaml ] && chk "service fan2go" '[ "$(systemctl is-active fan2go)" = active ]' "$(systemctl is-active fan2go)"

E=$(journalctl -k -b --no-pager 2>/dev/null | grep -ciE 'NVRM: Xid|IO_PAGE_FAULT|AER:')
chk "no Xid / IO_PAGE_FAULT / AER this boot" '[ "$E" = 0 ]' "$E lines"

if grep -q '^md' /proc/mdstat; then
  LV=$(awk '/^md/{print $1": "$4}' /proc/mdstat | tr '\n' ' ')
  chk "RAID level 1" '! grep -E "^md" /proc/mdstat | grep -vq raid1' "$LV"
  chk "RAID members all up" '! grep -q "_" <(grep -oE "\[[U_]+\]" /proc/mdstat)' "$(grep -oE '\[[U_]+\]' /proc/mdstat | tr '\n' ' ')"
  chk "no RAID resync running" '! grep -qE "resync|recovery" /proc/mdstat' ""
  # mdadm --monitor exits at once when no array is redundant (RAID 0 only): mdmonitor then
  # "fails" with "Can't open PID file". That is a consequence of RAID 0, not a separate fault.
  if grep -E "^md" /proc/mdstat | grep -qE "raid(1|4|5|6|10)"; then
    chk "mdmonitor running" '[ "$(systemctl is-active mdmonitor)" = active ]' "$(systemctl is-active mdmonitor)"
  else
    info "mdmonitor" "nothing to monitor: no redundant array (see RAID level)"
  fi
  chk "mdadm reports somewhere" 'grep -qE "^(MAILADDR|PROGRAM)" /etc/mdadm.conf /etc/mdadm/mdadm.conf 2>/dev/null' ""
fi

chk "sshd: no root login" '[ "$(sshd -T | awk "/^permitrootlogin /{print \$2}")" = no ]' "$(sshd -T | awk '/^permitrootlogin /{print $2}')"
info "sshd: password login" "$(sshd -T | awk '/^passwordauthentication /{print $2}')"
chk "root has no password" '[[ "$(getent shadow root | cut -d: -f2)" == "!"* || "$(getent shadow root | cut -d: -f2)" == "*"* ]]' ""
chk "clock synchronized" '[ "$(timedatectl show -p NTPSynchronized --value)" = yes ]' ""
if [ $ROCKY = 1 ]; then info "firewall services" "$(firewall-cmd --list-services)"; else info "firewall" "$(ufw status | head -1)"; fi
info "Cockpit" "$(systemctl is-active cockpit.socket 2>/dev/null)"
chk "boots without desktop" '[ "$(systemctl get-default)" = multi-user.target ]' "$(systemctl get-default)"
chk "sysctl panic_on_oom, panic" '[ "$(sysctl -n vm.panic_on_oom)" = 1 ] && [ "$(sysctl -n kernel.panic)" = 10 ]' ""
chk "tuned throughput-performance" 'tuned-adm active | grep -q throughput-performance' ""

DA=$(docker version --format '{{.Server.APIVersion}}' 2>/dev/null)
chk "Docker API 1.44 or later" '[ -n "$DA" ] && [ "$(printf "%s\n1.44\n" "$DA" | sort -V | head -1)" = 1.44 ]' "$DA"
chk "Docker nvidia runtime" 'docker info --format "{{json .Runtimes}}" | grep -q nvidia' ""
chk "GPUs in a container (runtime)" '[ "$(docker run --rm --gpus all ubuntu:24.04 nvidia-smi -L 2>/dev/null | grep -c ^GPU)" = "$NS" ]' ""
chk "GPUs in a container (CDI)" '[ "$(docker run --rm --device nvidia.com/gpu=all ubuntu:24.04 nvidia-smi -L 2>/dev/null | grep -c ^GPU)" = "$NS" ]' ""

echo; [ $fail = 0 ] && echo "ALL PASSED" || echo "$fail FAILED"
exit $fail
