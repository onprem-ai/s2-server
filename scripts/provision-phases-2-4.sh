#!/bin/bash
# s2-server 04-provisioning.md, Rocky Linux 10: Phase 2 (updates), IPMI tools + inventory,
# Phase 3 (kernel, NVIDIA 595 driver, persistence, power limit), Phase 4 (kernel command
# line, sysctl, journald, tuned). Safe to run again: each step checks what is already done.
set -euo pipefail
BRANCH=595
log() { echo; echo "=== $*"; }

log "Phase 2: bring the system current, security updates daily"
dnf install -y dnf-plugins-core python3-dnf-plugin-versionlock
dnf -y upgrade --refresh
dnf install -y dnf-automatic
sed -i -e 's/^upgrade_type *=.*/upgrade_type = security/' \
       -e 's/^apply_updates *=.*/apply_updates = yes/' \
       -e 's/^reboot *=.*/reboot = never/' /etc/dnf/automatic.conf
grep -E '^(upgrade_type|apply_updates|reboot) *=' /etc/dnf/automatic.conf
systemctl enable --now dnf-automatic.timer
dnf install -y ipmitool

NEWEST=$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' kernel-core | sort -V | tail -1)
if [ "$NEWEST" != "$(uname -r)" ]; then
  log "STOP: the upgrade installed kernel $NEWEST, running $(uname -r)."
  echo "Reboot (sudo systemctl reboot), then run this script again: the driver must be built for the running kernel."
  exit 0
fi

log "Inventory"
{
  hostnamectl; uname -r; cat /proc/cmdline
  lscpu | grep -E 'Model name|Socket|NUMA node\(s\)|^CPU\(s\)'
  free -g; lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL
  lspci -nn | grep -iE 'nvidia|3d controller|vga|ethernet|infiniband'
  for d in $(lspci -D -d 10de: | awk '/3D|VGA/{print $1}'); do
    echo "== $d"; lspci -vvv -s "$d" | grep -E 'LnkCap:|LnkSta:|Region 1'
  done
  mokutil --sb-state 2>/dev/null
  dmidecode -s system-product-name; dmidecode -s bios-version
  dmidecode -t 17 | grep -E '^\s(Size|Locator|Part Number|Speed|Configured Memory Speed):'
} 2>&1 | tee /root/inventory-$(date +%Y%m%d).txt


log "Phase 3: kernel headers, DKMS"
dnf config-manager --set-enabled crb
dnf install -y epel-release
dnf install -y kernel-devel-matched kernel-headers dkms

log "Phase 3: nouveau off, GPUs never powered down"
cat > /etc/modprobe.d/blacklist-nouveau.conf <<'X'
blacklist nouveau
options nouveau modeset=0
X
cat > /etc/modprobe.d/nvidia-inference-node.conf <<'X'
# Headless machine: no kernel mode setting on the NVIDIA GPUs.
options nvidia-drm modeset=0
# Never power the GPUs down when idle (runtime D3 / GC6).
options nvidia NVreg_DynamicPowerManagement=0x00
X

log "Phase 3: NVIDIA repository, branch $BRANCH locked, driver"
dnf config-manager --add-repo \
  https://developer.download.nvidia.com/compute/cuda/repos/rhel10/x86_64/cuda-rhel10.repo
dnf clean expire-cache
# dnf 4's versionlock cannot parse a * inside the package name: one line per package.
sed -i "/3:${BRANCH}\*/d" /etc/dnf/plugins/versionlock.list 2>/dev/null || true
for p in kmod-nvidia-open-dkms nvidia-kmod-common nvidia-modprobe nvidia-open \
         nvidia-persistenced nvidia-driver nvidia-driver-libs nvidia-driver-cuda \
         nvidia-driver-cuda-libs libnvidia-cfg libnvidia-fbc libnvidia-gpucomp libnvidia-ml; do
  echo "${p}-3:${BRANCH}*" >> /etc/dnf/plugins/versionlock.list
done
cat /etc/dnf/plugins/versionlock.list
dnf install -y nvidia-driver-cuda kmod-nvidia-open-dkms
command -v nvidia-smi nvidia-persistenced
for p in nvidia-driver-cuda kmod-nvidia-open-dkms; do
  v=$(rpm -q --qf '%{VERSION}' "$p"); echo "$p $v"
  case "$v" in ${BRANCH}.*) ;; *) echo "STOP: $p is $v, not branch ${BRANCH}"; exit 1;; esac
done
dracut -f --regenerate-all
dkms status | grep -i nvidia
dnf versionlock add kernel kernel-core kernel-modules kernel-modules-core \
  kernel-modules-extra kernel-devel kernel-devel-matched kernel-headers
dnf versionlock list

log "Phase 3: persistence mode, 500 W power limit at every boot"
USER_OPTION=$(id nvidia-persistenced >/dev/null 2>&1 && echo "--user nvidia-persistenced" || true)
mkdir -p /etc/systemd/system/nvidia-persistenced.service.d
cat > /etc/systemd/system/nvidia-persistenced.service.d/10-persistence-mode.conf <<X
[Service]
ExecStart=
ExecStart=/usr/bin/nvidia-persistenced ${USER_OPTION} --verbose
X
cat > /etc/systemd/system/nvidia-power-limit.service <<'X'
[Unit]
Description=Set the NVIDIA GPU power limit (500 W per GPU)
After=nvidia-persistenced.service
Wants=nvidia-persistenced.service

[Service]
Type=oneshot
ExecStart=/usr/bin/nvidia-smi --power-limit=500
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
X
systemctl daemon-reload
systemctl enable nvidia-persistenced nvidia-power-limit

log "Phase 4: kernel command line (PCIe power management off, IOMMU passthrough)"
grubby --update-kernel=ALL --args="pcie_aspm=off pcie_port_pm=off iommu=pt"
grubby --update-kernel=ALL --remove-args="rhgb quiet"
grubby --info=ALL | grep -E '^(kernel|args)'

log "Phase 4: sysctl, journald, tuned"
cat > /etc/sysctl.d/60-onprem-ai.conf <<'X'
fs.inotify.max_user_instances = 1024
fs.inotify.max_user_watches = 1048576
vm.panic_on_oom = 1
kernel.panic = 10
X
sysctl --system >/dev/null
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/60-onprem-ai.conf <<'X'
[Journal]
SystemMaxUse=2G
SystemMaxFileSize=100M
MaxRetentionSec=30day
X
systemctl restart systemd-journald
dnf install -y tuned
systemctl enable --now tuned && tuned-adm profile throughput-performance

log "Secure Boot"
if mokutil --sb-state 2>/dev/null | grep -q enabled; then
  if mokutil --test-key /var/lib/dkms/mok.pub 2>/dev/null | grep -q "already enrolled"; then
    echo "DKMS key already enrolled."
  else
    echo "Secure Boot is on: the driver loads only after DKMS's key is enrolled."
    echo "Choose a one-time password now (asked twice); at the next boot the console shows"
    echo "the MOK manager: press a key within 10 s, Enroll MOK, Continue, Yes, the password, Reboot."
    mokutil --import /var/lib/dkms/mok.pub
  fi
fi

log "DONE. Reboot now: sudo systemctl reboot"
