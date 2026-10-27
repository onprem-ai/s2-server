# 04 Provisioning: operating system to container runtime

This runbook takes an assembled and brought-up machine ([02](02-assembly.md),
[03](03-bring-up.md)) to the point where the
one-line install (`curl -fsSL https://get.onprem.ai/node | sh -s -- ...`) gives a
healthy inference node that runs models in containers. The platform installs and
updates its own software; everything here is the part it does not own: firmware, the
operating system, the kernel, the NVIDIA driver, Docker and the NVIDIA Container
Toolkit.

Scope: NVIDIA GPUs on bare-metal x86-64 machines with Ubuntu 24.04 LTS or Rocky
Linux 10. The commands assume a root shell (`sudo -i`). Where the two distributions
differ, a step gives one block for each, marked **Ubuntu 24.04** and **Rocky Linux
10**; a block with both in it names the distribution in a comment on each line that
differs. The outcome checks ([05 Acceptance](05-acceptance.md)) are the same for both. Other distributions need
the same outcome with their own package commands.

Every rule here comes from an incident on this class of hardware or from the vendor's
documentation; the evidence is linked at the step. The failures it prevents are not
subtle: a GPU that falls off the bus under load (Xid 79), a machine whose SSH hangs
from a PCIe error flood, every GPU container refused after an unattended driver
upgrade, a two-GPU model that hangs forever at its first NCCL collective.

The phases run in order, 1 to 7. Firmware and BIOS come before them in
[03 Bring-up](03-bring-up.md); the burn-in, the host checks and the platform install
come after them in [05 Acceptance](05-acceptance.md); later driver and kernel changes
and GPU failures are in [06 Operations](06-operations.md).

## Phase 1: install the operating system

- **Ubuntu 24.04:** Ubuntu Server 24.04 LTS, minimal install, OpenSSH server on. Do
  not select Docker or any other snap in the installer. Docker as a snap is not
  supported: its sandbox cannot see `/var/lib/onprem-ai`, where the model weights live.
- **Rocky Linux 10:** the "Minimal Install" or "Server" environment, without the
  "Container Management" group (it brings Podman, which Phase 5 removes). No desktop
  ("Server with GUI", "Workstation"): a desktop blanks and locks the screen, and through
  the remote console every typed command then lands in the lock screen's password
  field, and it holds RAM the models could use. Keep SELinux enforcing: the inference
  node is built and verified for it (Phase 5).

  Already installed with a desktop: switch it off, keep the packages. The machine then
  boots to a text login on the console; SSH is unchanged. The packages only take disk
  space, and `systemctl isolate graphical.target` brings the desktop back for a while.

  ```sh
  systemctl set-default multi-user.target    # boot without the desktop from now on
  systemctl isolate multi-user.target        # stop it now, no reboot
  systemctl get-default                      # multi-user.target
  ```
- In the installer, in this order:
  - **Root account: disabled** (Rocky Linux 10, "Root Account" screen; Ubuntu 24.04 has
    none). No root password, and never tick "Allow root SSH login with password":
    that writes `/etc/ssh/sshd_config.d/01-permitrootlogin.conf` with
    `PermitRootLogin yes`, which overrides later settings (see "SSH access" below).
  - User **`ops`** as an administrator (Rocky Linux 10: "Make this user
    administrator", group `wheel`; Ubuntu 24.04: the installer's user has `sudo`), with
    its final long password from the password manager (see "SSH access" below). `sudo`
    asks for this same password: there is no separate root password.
  - The host name `ain-xxxxx` (see below), so the machine never runs as
    `localhost.localdomain`.
- Every step after the install logs in as `ops` over SSH with a key and works as root
  with `sudo -i`. After the first boot, add the operator's key from the machine that
  runs the install, then check it:

  ```sh
  ssh-copy-id -i ~/.ssh/id_ed25519.pub ops@<host address>   # asks once for ops's password
  ssh -t ops@<host address> 'sudo true && echo sudo-ok'    # no password asked for the key
  ```

  Without password login over SSH, at the console as `ops`: append the public key to
  `~/.ssh/authorized_keys` (directory `700`, file `600`), and on Rocky Linux 10 run
  `restorecon -R ~/.ssh` so SELinux lets `sshd` read it.
- **SSH access.** Root never logs in over SSH; administrators log in as `ops` and use
  `sudo -i`.

  - **Default: long password.** `ops` gets a long, unique password (at least 16
    random characters, kept in the password manager). It is needed for `sudo` and at
    the console anyway, and it keeps a way in when no key is at hand. Password login
    over SSH stays on, so anyone on the network can keep guessing that password: a
    short or reused one is not acceptable.
  - **Optional: key only.** Turn password login over SSH off when every administrator
    has a key. The `ops` password is then only for `sudo` and the console. Test a key
    login in a second window before reloading `sshd`, and keep the first session open
    until it works.

  Installed as above, only the check is needed. To fix a machine installed otherwise:
  `sshd` takes the **first** value it reads, and it reads `sshd_config.d/` in file-name
  order, so the installer's `01-permitrootlogin.conf` wins over any later file: remove
  it. Removing root's password does not change `ops` or `sudo`.

  ```sh
  passwd ops                                   # the long password, from the password manager
  usermod -p '!' root                          # root has no password (never passwd -d: that leaves it empty)
  grep -r PermitRootLogin /etc/ssh/sshd_config.d/   # an installer file saying yes?
  rm -f /etc/ssh/sshd_config.d/01-permitrootlogin.conf
  echo 'PermitRootLogin no' > /etc/ssh/sshd_config.d/10-no-root.conf
  # optional, key only:
  echo 'PasswordAuthentication no' > /etc/ssh/sshd_config.d/11-key-only.conf
  sshd -t && systemctl reload sshd             # syntax check, then apply
  sshd -T | grep -iE '^(permitrootlogin|passwordauthentication) '   # no; yes (default) or no (key only)
  ```

  Rocky Linux 10 also opens its browser admin console (Cockpit, port 9090, announced in
  the SSH login banner). Nothing here uses it: turn it off now (also in Phase 7,
  "Firewall and time"):

  ```sh
  systemctl disable --now cockpit.socket
  firewall-cmd --permanent --remove-service=cockpit && firewall-cmd --reload
  ```
- A static IP address or a DHCP reservation, and a host name that will not change.
  The inference node joins under the machine's host name, and the control plane shows
  that name on **Servers**; an installer default such as `localhost.localdomain` makes
  every machine look the same there. Set a unique name before the install ([05](05-acceptance.md)),
  `ain-` and five random characters, unless your naming scheme gives one:

  ```sh
  hostnamectl set-hostname "ain-$(tr -dc 'a-z0-9' </dev/urandom | head -c 5)"
  hostnamectl --static      # the new name, for the machine's record
  ```

  Record the name in the [machine record](machine-record.md), with the inventory below. A machine renamed after the install shows
  its new name on **Servers** once the inference node reconnects
  (`systemctl restart onprem-ai-inference-node`); a nickname set there takes precedence over it.
- Disks: the S2's two NVMe disks form **one RAID 1 mirror** (Linux software RAID,
  `mdadm`), and everything lives on it: system, model weights, model images. When one
  disk fails, the machine keeps running on the other and the failed disk is replaced
  on a planned visit ([06](06-operations.md)). Usable space is one disk: 2 TB. Not
  RAID 0: there one failed disk loses the system and every model on the machine.
  Exception, for compute-only nodes that store nothing that cannot be downloaded again:
  [RAID 0 option](options/raid0-compute-only.md).

  Layout, the same on both disks (set it in the installer's custom partitioning):

  | Partition | Size | On both disks | Holds |
  |---|---|---|---|
  | EFI system partition | 1 GB | Rocky Linux 10: one RAID 1 (`mdadm` metadata 1.0, which the installer picks for `/boot/efi`). Ubuntu 24.04: one ESP per disk, the second added as "another boot device" | `/boot/efi` |
  | `/boot` | 2 GB | RAID 1 | Kernels, initramfs |
  | Rest | All the rest | RAID 1 | `/` (ext4 or XFS), on LVM if wanted |

  A boot loader on both disks is the point: with the ESP on one disk only, the machine
  runs on after that disk fails but does not boot again. Pick the two NVMe disks by
  model and size in the installer.

  The model weights and the model images are the largest things on the machine, often
  several hundred gigabytes each:

  | Path | Holds | Size it for |
  |---|---|---|
  | `/var/lib/onprem-ai` | Model weights (default location), the node's data | Twice the largest model you will deploy, plus every model you keep |
  | `/var/lib/docker` | Model images (vLLM, SGLang images are 10 to 25 GB each) | 200 GB or more |

  One large root file system on the mirror is fine. Separate logical volumes for
  `/var/lib/onprem-ai` and `/var/lib/docker` (ext4 or XFS, mounted `noatime`) keep a
  full model store from filling `/`. The model weights directory can also move later
  from the control plane (**Servers**, the node, **Config**).

  After the first boot, check the mirror and have failures reported:

  ```sh
  cat /proc/mdstat                                   # every array [UU]; resync may still run
  mdadm --detail --scan
  mdadm --detail /dev/md/* | grep -E '^/dev|State :|Active Devices'
  efibootmgr -v                                      # Rocky: one entry; Ubuntu: one per disk
  ```

  `mdadm` reports a failed member only to someone listening. Rocky Linux 10 runs
  `mdmonitor.service`; give it a mail address or a program in `/etc/mdadm.conf`
  (`MAILADDR` or `PROGRAM`), and check `systemctl is-active mdmonitor`. Ubuntu runs the
  same monitor from the `mdadm` package (`/etc/mdadm/mdadm.conf`). A degraded mirror
  keeps serving with no sign at all: the [05](05-acceptance.md) check and the node's
  health checks must read `/proc/mdstat`.

  The IPMI card adds disks of its own: its virtual media show up as `sda` ("Virtual
  HDisk0", 0 bytes) and `sr0` ("Virtual CDROM0"). In the installer, pick the two NVMe
  disks by model and size, never `sda`; in scripts and `/etc/fstab`, name disks by
  `/dev/disk/by-id/` or UUID, not `sda`/`nvme0n1`.
- Swap: keep what the installer creates (Rocky Linux 10: a swap volume sized from the
  RAM; Ubuntu 24.04: a swap file). Check after the first boot with `swapon --show`.

### IPMI card tools

Install `ipmitool`: it talks to the IPMI card over the network (`-I lanplus`), for
power control and the card's sensors.

```sh
dnf install -y ipmitool                          # Rocky Linux 10
apt-get install -y ipmitool                      # Ubuntu 24.04
```

On the public BIOS, `ipmitool` on the host cannot reach the card directly: the card's
host interface needs a special BIOS from ASUS support, and the kernel reports
`ipmi_si ...: Interface detection failed` with no `/dev/ipmi0`. Expected, harmless
([`hardware/ipmi-card/`](hardware/ipmi-card/README.md#access-from-the-host-in-band-needs-the-special-ipmi-bios)).

After the first boot, collect the inventory. Keep the output with the machine's
record ([machine-record.md](machine-record.md)); it is what support asks for first.

```sh
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
} 2>&1 | tee /root/inventory-$(date +%Y%m%d).txt
```

## Phase 2: automatic updates

An inference node runs for months without a person logging in. It must get the
operating system's security fixes on its own, and it must never change its GPU stack
on its own.

| Part | Updates | Why |
|---|---|---|
| Operating system packages (OpenSSH, OpenSSL, glibc, systemd, ...) | Security fixes, automatically, every day | A machine nobody logs into is otherwise patched never |
| GPU stack: kernel, NVIDIA driver, NVIDIA Container Toolkit, Docker, containerd | Never automatically; only in a planned change with a reboot ([06](06-operations.md)) | See below |
| The inference node software | From the control plane (**Updates**) | Not the operating system's package manager's |
| Model images and engines | From the control plane, per deployment | Pinned by digest |
| Reboots | Never automatically | A reboot stops every model on the machine; schedule it ([06](06-operations.md)) |

A driver, kernel or toolkit upgrade that happens without a person deciding it is the
most expensive failure on record: `unattended-upgrades` replaced the NVIDIA userspace,
the old kernel module stayed loaded, and every GPU container was refused with
`driver/library version mismatch` for 8 hours
([260521](learnings/260521-nvidia-driver-version-mismatch.md)). A new kernel is the
same risk one boot later: the NVIDIA module must be rebuilt for it, and when that
fails the machine starts without GPUs.

How each distribution keeps the two apart:

- **Ubuntu 24.04:** `unattended-upgrades` installs security updates daily; a package
  blacklist keeps the GPU stack out of it, and `apt-mark hold` (Phase 3) keeps the
  kernel out of every other `apt` run.
- **Rocky Linux 10:** `dnf-automatic` installs security updates daily; the dnf version
  lock (Phases 3 and 5) keeps the GPU stack out of every dnf run, `dnf-automatic`
  included (it applies the lock rules,
  [Red Hat bug 1746562](https://bugzilla.redhat.com/show_bug.cgi?id=1746562)).

Security updates of libraries keep running processes on the old copy until they
restart. Neither distribution restarts Docker or reboots on its own with the settings
below: a reboot is a planned step ([06](06-operations.md)), and the check below names what waits
for one.

**Ubuntu 24.04:** keep `unattended-upgrades` for the operating system and exclude the
GPU stack from it.

```sh
cat > /etc/apt/apt.conf.d/51onprem-ai-gpu-stack <<'EOF'
Unattended-Upgrade::Package-Blacklist {
    "nvidia-.*";
    "libnvidia-.*";
    "cuda-.*";
    "linux-image-.*";
    "linux-headers-.*";
    "linux-modules-.*";
    "linux-generic.*";
    "linux-hwe-.*";
    "docker-ce.*";
    "containerd.io";
};
EOF

# needrestart restarts services after library upgrades. Restarting Docker stops every
# model on the machine; never let it do that on its own.
mkdir -p /etc/needrestart/conf.d
cat > /etc/needrestart/conf.d/50-onprem-ai.conf <<'EOF'
$nrconf{override_rc}{qr(^docker)} = 0;
$nrconf{override_rc}{qr(^containerd)} = 0;
$nrconf{override_rc}{qr(^onprem-ai)} = 0;
EOF

# Telemetry that serves no purpose on an appliance.
systemctl disable --now motd-news.timer 2>/dev/null
sed -i 's/^ENABLED=1/ENABLED=0/' /etc/default/motd-news 2>/dev/null

# Bring the base system current once, before anything is pinned.
apt-get update && apt-get -y full-upgrade
```

On an air-gapped machine, also disable `apt-daily.timer` and `apt-daily-upgrade.timer`:
they only produce daily failures there.

**Rocky Linux 10:** a fresh install updates nothing on its own (`dnf-automatic` is not
installed; `dnf-makecache.timer` only refreshes the package lists). Install it and
limit it to security updates:

```sh
dnf install -y dnf-plugins-core python3-dnf-plugin-versionlock
dnf -y upgrade --refresh                         # current once, before anything is locked

dnf install -y dnf-automatic
sed -i -e 's/^upgrade_type *=.*/upgrade_type = security/' \
       -e 's/^apply_updates *=.*/apply_updates = yes/' \
       -e 's/^reboot *=.*/reboot = never/' /etc/dnf/automatic.conf
grep -E '^(upgrade_type|apply_updates|reboot) *=' /etc/dnf/automatic.conf
systemctl enable --now dnf-automatic.timer
systemctl list-timers dnf-automatic.timer       # daily at 06:00, up to 60 minutes later
```

`reboot = never` is the package's default; the line keeps it so after a package
update rewrites the file.

On an air-gapped machine, leave `dnf-automatic` out and disable `dnf-makecache.timer`.

### Check the updates

Look at these after the first day and after every maintenance visit:

```sh
# Ubuntu 24.04
tail -n 20 /var/log/unattended-upgrades/unattended-upgrades.log   # what was installed
cat /var/run/reboot-required.pkgs 2>/dev/null                    # what waits for a reboot
apt-mark showhold                                                # the kernel is held

# Rocky Linux 10
journalctl -u dnf-automatic --since "-2 days" --no-pager         # what was installed
dnf needs-restarting -r                                          # what waits for a reboot
dnf versionlock list                                             # the GPU stack is locked
```

A pending reboot is not urgent: plan it with the next maintenance ([06](06-operations.md)). A
pending reboot right after Phase 3 is expected; it lists the NVIDIA driver, whose
kernel module loads at the next boot.

On both distributions: when the first upgrade brought a new kernel, reboot before
Phase 3, so the driver is built for the kernel that runs. The kernel and the NVIDIA
packages are held in Phase 3, after they are installed.

## Phase 3: kernel and NVIDIA driver

### Kernel

Use the kernel the fleet already runs with the chosen driver, and keep it. A new
kernel triggers a DKMS rebuild of the NVIDIA module; when that rebuild fails, the
machine boots without a GPU driver. Both known kernel incidents were caused by a
kernel change, not by the driver: the Ubuntu HWE move from 6.14 to 6.17 made nouveau
hang the boot on Blackwell and changed AER handling
([260529](learnings/260529-blackwell-boot-hang-newer-kernels.md)), and a
6.8 point release caused Xid 79 on RTX PRO 5000 Blackwell
([260526](learnings/260526-gpu-pcie-drop-recovery.md), Ubuntu bug 2152037).

**Ubuntu 24.04:**

```sh
apt-get install -y linux-headers-$(uname -r) dkms build-essential
```

Install the HWE kernel (`linux-generic-hwe-24.04`) only when the hardware needs it,
for example a NIC or a CPU the GA kernel does not support, and then reboot into it
before Phase 3 continues.

**Rocky Linux 10:** the release keeps one kernel line (6.12) for its whole life and
backports fixes into it. DKMS comes from EPEL, which needs the CRB repository
([NVIDIA, Rocky Linux](https://docs.nvidia.com/datacenter/tesla/driver-installation-guide/latest/rocky-linux.html)):

```sh
dnf config-manager --set-enabled crb
dnf install -y epel-release
dnf install -y kernel-devel-matched kernel-headers dkms
```

### Keep nouveau away, keep the GPUs powered

```sh
cat > /etc/modprobe.d/blacklist-nouveau.conf <<'EOF'
blacklist nouveau
options nouveau modeset=0
EOF
cat > /etc/modprobe.d/nvidia-inference-node.conf <<'EOF'
# Headless machine: no kernel mode setting on the NVIDIA GPUs.
options nvidia-drm modeset=0
# Never power the GPUs down when idle (runtime D3 / GC6). The GPU stays on and
# saves power only with its own clocks and voltages.
options nvidia NVreg_DynamicPowerManagement=0x00
EOF
update-initramfs -u                              # Ubuntu 24.04
dracut -f --regenerate-all                       # Rocky Linux 10
```

`NVreg_DynamicPowerManagement=0x00` turns off runtime D3: the driver then never cuts
the power to an idle GPU and keeps it on the bus. Every power transition of an idle
GPU is a chance for it not to come back; on Blackwell, GSP firmware faults around
these transitions end in Xid 79, the GPU fallen off the bus, the same failure class
as the link power management that Phase 4 turns off
([260526](learnings/260526-gpu-pcie-drop-recovery.md); NVIDIA
open-gpu-kernel-modules issues
[#1064](https://github.com/NVIDIA/open-gpu-kernel-modules/issues/1064) and
[#1151](https://github.com/NVIDIA/open-gpu-kernel-modules/issues/1151)).

What it changes on a desktop board: the driver's default (`0x03`) already disables
runtime D3 on desktop systems
([NVIDIA driver README, RTD3](https://download.nvidia.com/XFree86/Linux-x86_64/595.71.05/README/dynamicpowermanagement.html)),
and `/proc/driver/nvidia/gpus/<bus>/power` on an S2 reads
`Runtime D3 status: Disabled by default`. The explicit `0x00` keeps that true whatever
the driver detects the machine to be, and after a driver update changes the default.
It costs nothing on such a machine, and about 10 W per GPU where runtime D3 was active.

An RTX PRO 6000 with a model loaded and no requests draws about 93 W and stays in
performance state P0 at full clock (measured on an S2: 97 GB of
memory in use, 0 percent utilization, about 2360 MHz). The inference engine holds the
GPU, so it never drops to its idle states. That is the normal draw of a serving GPU,
not a fault: plan about 100 W per GPU as the floor of the machine's power use.

Check after the reboot in [05 Acceptance](05-acceptance.md):

```sh
grep DynamicPowerManagement: /proc/driver/nvidia/params      # DynamicPowerManagement: 0
grep 'Runtime D3 status' /proc/driver/nvidia/gpus/*/power    # Disabled
```

### Choose the driver branch

| Hardware | Branch | Note |
|---|---|---|
| RTX PRO 6000 Blackwell, RTX 50 series (consumer and workstation Blackwell) | 595 (tested: 595.71.05 on Ubuntu 24.04, 595.112.07 on Rocky Linux 10) | Open kernel modules are required on Blackwell |
| Data center (H100, H200, B200, L40S) | The current production branch the vendor certifies the system for | Check the system vendor's support matrix first |

Every NVIDIA package on the machine, and on HGX systems `nvidia-fabricmanager`, must
come from the same driver version. Containers bring their own CUDA runtime; the host
needs only the driver. Never install the CUDA toolkit on the host.

### Install

The driver comes from NVIDIA's repository, with the branch pinned before the driver
is installed (NVIDIA's recommended order,
[Version locking](https://docs.nvidia.com/datacenter/tesla/driver-installation-guide/version-locking.html)):

**Ubuntu 24.04:**

```sh
BRANCH=595
curl -fsSLo /tmp/cuda-keyring.deb \
  https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb
dpkg -i /tmp/cuda-keyring.deb && apt-get update

apt-get install -y nvidia-driver-pinning-${BRANCH}
# Headless, open kernel modules: no X, GL or Vulkan userspace.
apt-get install -y -V nvidia-headless-open
command -v nvidia-smi nvidia-persistenced      # both answer
```

`nvidia-headless-open` is NVIDIA's metapackage for a machine without a display: it
pulls `nvidia-dkms-open` (the kernel module), `nvidia-kernel-common` and
`libnvidia-compute`, which holds the CUDA driver library, NVML, `nvidia-smi` and, as
a dependency, `nvidia-persistenced`. Checked against NVIDIA's repository for
595.91.07: `nvidia-smi` is in the `libnvidia-compute` package itself. The desktop
metapackage (`nvidia-open`) adds the X server driver and the GL, video and display
libraries a headless machine never uses. Package set from NVIDIA's
[Ubuntu installation guide](https://docs.nvidia.com/datacenter/tesla/driver-installation-guide/ubuntu.html),
"Compute-only (Headless)".

**Rocky Linux 10:** NVIDIA's `rhel10` repository serves Rocky Linux 10. It has no
pinning package; the branch is locked with dnf's version lock before the install, in
NVIDIA's own form
([Version locking, DNF 4](https://docs.nvidia.com/datacenter/tesla/driver-installation-guide/version-locking.html)):

```sh
BRANCH=595
dnf config-manager --add-repo \
  https://developer.download.nvidia.com/compute/cuda/repos/rhel10/x86_64/cuda-rhel10.repo
dnf clean expire-cache

# One line per package: dnf 4's versionlock cannot parse a * inside the package name
# ("could not parse pattern: libnvidia*3:595*"); such a line locks nothing, and dnf
# then picks the newest branch.
for p in kmod-nvidia-open-dkms nvidia-kmod-common nvidia-modprobe nvidia-open \
         nvidia-persistenced nvidia-driver nvidia-driver-libs nvidia-driver-cuda \
         nvidia-driver-cuda-libs libnvidia-cfg libnvidia-fbc libnvidia-gpucomp libnvidia-ml; do
  echo "${p}-3:${BRANCH}*" >> /etc/dnf/plugins/versionlock.list
done

# Compute-only, open kernel modules: no X, GL or Vulkan userspace.
dnf install -y nvidia-driver-cuda kmod-nvidia-open-dkms
command -v nvidia-smi nvidia-persistenced      # both answer
rpm -q nvidia-driver-cuda kmod-nvidia-open-dkms   # both on the branch, epoch 3
```

`nvidia-driver-cuda` holds `nvidia-smi` and needs `nvidia-persistenced`;
`kmod-nvidia-open-dkms` builds the open kernel module with DKMS. Checked against
NVIDIA's repository for 595.112.07. The package set is NVIDIA's compute-only one for
Rocky Linux; the desktop set (`nvidia-open`) adds the display libraries.

HGX and other NVSwitch systems also need the fabric manager, same version, running:

```sh
apt-get install -y nvidia-fabricmanager      # Ubuntu 24.04
dnf install -y nvidia-fabricmanager          # Rocky Linux 10
systemctl enable nvidia-fabricmanager
```

Secure Boot on (the S2 ships with it on): the module DKMS builds must be signed with a
key the firmware trusts, or it does not load and `nvidia-smi` reports no device.
Either turn Secure Boot off in the BIOS ([03 Bring-up](03-bring-up.md), the route used on the S2), or enroll DKMS's key once, from
the BMC's remote console:

- **Ubuntu 24.04:** DKMS asks for a MOK password during the install.
- **Rocky Linux 10:** `mokutil --import /var/lib/dkms/mok.pub` asks for a one-time
  password.

At the next boot, the console shows the MOK manager; choose **Enroll MOK** and enter
that password.

Confirm the module was built for the running kernel, then hold the GPU stack.

**Ubuntu 24.04:**

```sh
dkms status | grep -i nvidia             # "installed" for $(uname -r)
apt-mark hold "linux-image-$(uname -r)" "linux-headers-$(uname -r)" \
  "linux-modules-$(uname -r)" linux-generic linux-image-generic linux-headers-generic \
  linux-generic-hwe-24.04 linux-image-generic-hwe-24.04 linux-headers-generic-hwe-24.04 2>/dev/null
apt-mark showhold
```

The pinning package keeps the NVIDIA packages on the branch. The holds keep the
kernel. The blacklist from Phase 2 keeps both away from unattended upgrades.

**Rocky Linux 10:**

```sh
dkms status | grep -i nvidia             # "installed" for $(uname -r)
dnf versionlock add kernel kernel-core kernel-modules kernel-modules-core \
  kernel-modules-extra kernel-devel kernel-devel-matched kernel-headers
dnf versionlock list
```

The branch lines keep the NVIDIA packages on the branch; the kernel lines keep the
installed kernel. Every dnf run respects them, `dnf-automatic` included.

### Persistence

Without persistence mode, the driver tears the GPU state down whenever no process
holds the device and builds it again on the next open, which adds seconds to every
model start and every telemetry query in between.

Ubuntu's unit starts the daemon with `--no-persistence-mode`, so the daemon runs and
the GPUs still show persistence mode `Disabled`. The unit of NVIDIA's Rocky Linux 10 package starts it without that
flag (checked in 595.112.07). The override below gives both the same start, as the
daemon's own account where the package made one:

```sh
systemctl cat nvidia-persistenced | grep ExecStart
USER_OPTION=$(id nvidia-persistenced >/dev/null 2>&1 && echo "--user nvidia-persistenced")
mkdir -p /etc/systemd/system/nvidia-persistenced.service.d
cat > /etc/systemd/system/nvidia-persistenced.service.d/10-persistence-mode.conf <<EOF
[Service]
ExecStart=
ExecStart=/usr/bin/nvidia-persistenced ${USER_OPTION} --verbose
EOF
systemctl daemon-reload
systemctl enable nvidia-persistenced
```

[05 Acceptance](05-acceptance.md) checks the result: `persistence_mode` must read `Enabled` for every GPU.

### Power limit

Run every GPU at 500 W. The RTX PRO 6000 Blackwell allows 300 to 600 W and ships at
600 W. At 600 W the GPU hits its limit, drops its clocks and boosts again in a loop
(312 seconds of power capping in one concurrency test on an S2); the loss at
500 W is small for inference, which waits on memory more than on compute. The 500 W
limit also keeps two GPUs and the CPU inside what a desktop PSU delivers, and it is
the limit the S2 cooling was tested at (Phase 6). On other GPUs, choose the limit the
same way and write it in the machine's record.

`nvidia-smi -pl` does not survive a reboot. Set it at every boot:

```sh
cat > /etc/systemd/system/nvidia-power-limit.service <<'EOF'
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
EOF
systemctl daemon-reload
systemctl enable --now nvidia-power-limit
nvidia-smi --query-gpu=index,power.limit,power.min_limit,power.max_limit --format=csv
```

`nvidia-smi --power-limit` without `-i` sets every GPU. A value outside the GPU's own
range is refused, and the unit then fails: `systemctl status nvidia-power-limit` shows
the reason.

## Phase 4: kernel parameters and system tuning

### Kernel command line

| Parameter | Set it when | Why |
|---|---|---|
| `pcie_aspm=off pcie_port_pm=off` | Always on GPU machines | Link power management retrains the link between Gen1 at idle and Gen5 under load; on Blackwell this caused Surprise Link Down and Xid 79, the GPU fell off the bus during inference ([260526](learnings/260526-gpu-pcie-drop-recovery.md)). The idle power cost is a few watts |
| `iommu=pt` | Always; essential with two or more GPUs | With DMA remapping, GPU peer-to-peer writes fault (`IO_PAGE_FAULT` in `dmesg`) and the first NCCL collective of a tensor-parallel model hangs forever at 100% GPU ([260718](learnings/260718-amd-vi-iommu-nccl-p2p-hang.md)). Passthrough keeps the IOMMU on for interrupt remapping and VFIO |
| `pci=noaer` | Only after an AER flood is observed | Suppresses the correctable-error flood that hung SSH on a Blackwell machine ([260211](learnings/260211-ssh-hang-pcie-gpu-errors.md)), but it also hides the errors that announce an Xid 79 ([260526](learnings/260526-gpu-pcie-drop-recovery.md), "`pci=noaer` masks diagnostics"). Start without it and watch the `dmesg` check in [05](05-acceptance.md) |
| `numa_balancing=disable` | Machines with more than one NUMA node | Automatic NUMA page migration adds page faults to GPU-heavy processes ([NVIDIA](https://docs.nvidia.com/dccpu/grace-perf-tuning-guide/os-settings.html), [AMD](https://instinct.docs.amd.com/projects/system-acceptance/en/latest/common/os-tuning.html)) |
| `console=tty0 console=ttyS0,115200n8` | The BMC offers serial over LAN | Kernel messages of a hang reach the BMC |

**Ubuntu 24.04:**

```sh
cat > /etc/default/grub.d/90-onprem-ai-gpu.cfg <<'EOF'
# GPU inference node: see s2-server repo, 04-provisioning.md, Phase 4.
GRUB_CMDLINE_LINUX_DEFAULT="$GRUB_CMDLINE_LINUX_DEFAULT pcie_aspm=off pcie_port_pm=off iommu=pt"
EOF
update-grub
```

The file name sorts after the distribution's own drop-ins, so the line appends to
their value instead of replacing it. One file per machine role keeps the parameters
reviewable: `cat /etc/default/grub.d/90-onprem-ai-gpu.cfg` answers what was added and
why.

**Rocky Linux 10:** `grubby` writes the parameters into the boot entry of every
installed kernel. `rhgb quiet` hides the kernel's messages on the console; a server
needs them there.

```sh
grubby --update-kernel=ALL --args="pcie_aspm=off pcie_port_pm=off iommu=pt"
grubby --update-kernel=ALL --remove-args="rhgb quiet"
grubby --info=ALL | grep -E '^(kernel|args)'
```

After every kernel change ([06](06-operations.md)), check that the new kernel's entry carries the
parameters too; the `/proc/cmdline` check in [05](05-acceptance.md) shows it after the reboot.

### sysctl

```sh
cat > /etc/sysctl.d/60-onprem-ai.conf <<'EOF'
# Monitoring and containers need more inotify instances than the default 128
# (learnings/260227-cadvisor-inotify-exhaustion.md).
fs.inotify.max_user_instances = 1024
fs.inotify.max_user_watches = 1048576
# A host-wide out-of-memory can hang the machine. Panic and reboot instead: a reboot
# is recoverable, a hang needs a person. Container memory limits are cgroup limits
# and are not affected.
vm.panic_on_oom = 1
kernel.panic = 10
EOF
sysctl --system
```

`kernel.panic = 10` is the needed second half: `vm.panic_on_oom` alone stops the
machine at the panic screen. These two settings do not cover a reclaim thrash
where no out-of-memory event ever fires
([260925](learnings/260925-host-test-memory-exhaustion-thrash-crash.md)); what
prevents that is running nothing heavy on the host outside containers, and a memory
limit on every container.

### Logs and CPU

```sh
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/60-onprem-ai.conf <<'EOF'
[Journal]
SystemMaxUse=2G
SystemMaxFileSize=100M
MaxRetentionSec=30day
EOF
systemctl restart systemd-journald

apt-get install -y tuned                         # Ubuntu 24.04
dnf install -y tuned                             # Rocky Linux 10
systemctl enable --now tuned && tuned-adm profile throughput-performance
```

## Phase 5: Docker Engine and the NVIDIA Container Toolkit

The inference node needs Docker Engine with API 1.44 or later (Docker 25 or later).
Docker Desktop and the snap are refused.

**Ubuntu 24.04:**

```sh
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release; echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# The toolkit comes from NVIDIA's repository added in Phase 3.
apt-get install -y nvidia-container-toolkit
nvidia-ctk runtime configure --runtime=docker
systemctl restart docker
```

**Rocky Linux 10:** remove Podman first; Docker's own guide lists it as conflicting
([Docker, RHEL](https://docs.docker.com/engine/install/rhel/)). Docker's package does
not start the daemon on its own. Accept Docker's signing key only when dnf shows the
fingerprint `060A 61C5 1B55 8A7F 742B 77AA C52F EB6B 621E 9F35`.

```sh
dnf remove -y podman runc
dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
dnf install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker

dnf config-manager --add-repo \
  https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo
dnf install -y nvidia-container-toolkit
nvidia-ctk runtime configure --runtime=docker
systemctl restart docker

dnf versionlock add docker-ce docker-ce-cli containerd.io nvidia-container-toolkit \
  nvidia-container-toolkit-base libnvidia-container-tools libnvidia-container1
```

SELinux stays enforcing. Docker CE starts with `selinux-enabled` off, so containers
run unconfined: they reach the GPUs and the model weights without a label, which is
the setup the inference node install is verified on. Do not set
`"selinux-enabled": true` in `daemon.json`: GPU containers then need the
`container_use_devices` boolean and the model weights a `container_file_t` label.

The inference node uses either route to the GPUs: the registered `nvidia` runtime that
`nvidia-ctk runtime configure` adds, or CDI (`nvidia.com/gpu=<UUID>`). Toolkit 1.18 and
later generate the CDI specification at every boot and driver change through
`nvidia-cdi-refresh` ([NVIDIA](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/cdi-support.html));
keep it enabled so both routes work:

```sh
systemctl enable --now nvidia-cdi-refresh.path
systemctl restart nvidia-cdi-refresh.service
nvidia-ctk cdi list
```

`/etc/docker/daemon.json` after this phase holds the `nvidia` runtime. Add only these
keys when they apply, and restart Docker after:

| Key | When |
|---|---|
| `"data-root": "/srv/docker"` | `/var/lib/docker` is not on the large NVMe file system |
| `"log-driver": "local"` with `"log-opts": {"max-size": "50m", "max-file": "3"}` | Always useful for containers the platform does not start; the platform sets its own limits on its containers |

Do not add users to the `docker` group. The inference node never uses the Docker
socket directly: it works through its own admission control, which only lets it
create containers of the node's own shape (`docs/security-overview.md`). A person in
the `docker` group is root on the machine.

## Phase 6: GPU cooling for passive cards

Skip this phase when the GPUs have their own fans, or when the chassis is a GPU server
whose BMC already drives its fans from GPU temperature.

Server edition cards (RTX PRO 6000 Blackwell Server Edition, L40S, H100 PCIe) have no
fans. Chassis fans blow through them. The board's firmware fan curves see only the CPU
and board temperatures, never the GPU: without a controller in the operating system,
the fans do not speed up under GPU load at all
([260720](learnings/260720-gpu-fan-hub-alphacool-es-guardian.md)).

The controller is [fan2go](https://github.com/markusressel/fan2go): one Go binary,
reads GPU temperatures through NVML, writes PWM to the board's fan channels through
the kernel's hwmon interface. It replaces nothing the platform does; it is part of the
machine like the BIOS fan curve.

### Wiring

Done at assembly ([02](02-assembly.md), "GPU fans"). On the S2 the two fans sit in
series in a duct in front of both GPUs, so both fans cool both GPUs and run on one
curve, set by the hotter GPU. The rule behind the wiring: high-pressure server fans draw more current than a board fan header gives (an Arctic
S12038-8K draws 2.2 A at 12 V, 3.2 A peak; a header gives about 1 A). Power them from
the PSU and give the header only the signal:

- Fan power (12 V, ground): from the PSU, one SATA power adapter per fan.
- PWM and tach: to the headers of fan channels 4 (GPU fan A) and 6 (GPU fan B), one
  fan per header, so each fan has its own RPM reading.
- Never power these fans from a header: its fuse trips, and the fan stops and starts
  every few seconds.

### Load the sensor drivers

```sh
echo nct6775 > /etc/modules-load.d/nct6775.conf      # the board's Super I/O chip (fans, PWM)
modprobe nct6775
apt-get install -y lm-sensors                        # Ubuntu 24.04
dnf install -y lm_sensors                            # Rocky Linux 10
sensors                                              # fan and temperature readings appear
```

`asus_ec_sensors` (CPU, CPU package, VRM, board temperatures on ASUS boards) loads on
its own when the kernel knows the board; for the ProArt X870E-CREATOR WIFI that is
kernel 6.17 or later. Ubuntu's HWE kernel has it. Rocky Linux 10's kernel 6.12 does
not: `modinfo asus_ec_sensors` answers "not found" there. Without it, use `k10temp`'s
`Tctl` as the CPU sensor (index 1, the platform name from `fan2go detect`).

When `sensors` shows no `nct67...` chip and `dmesg` reports an ACPI resource conflict
for its I/O ports, add `acpi_enforce_resources=lax` to the kernel parameters (Phase 4)
and reboot.

### Check the fan channels

On the S2 the GPU fans are on hwmon channels 4 (GPU fan A) and 6 (GPU fan B); the
configuration below uses them. The header names on the board (CHA_FAN1 ...) do not map
one to one to the channel numbers, so check that the cables went where
[02](02-assembly.md) says:

```sh
H=$(grep -l '^nct67' /sys/class/hwmon/hwmon*/name | xargs dirname)
for i in 1 2 3 4 5 6 7; do echo "fan$i $(cat $H/fan${i}_input) rpm"; done
```

Unplug GPU fan A's signal cable, read again: `fan4` must drop to 0. Plug it back and
repeat with GPU fan B: `fan6` must drop to 0. A different channel means the cable is on
the wrong header: move it, do not change the configuration. Write the result into the
machine's record.

### Install fan2go

```sh
FAN2GO_VERSION=0.15.0
FAN2GO_SHA256=3695af6c3e6147d7b8401e94f3991fc1cd144c7e18b26e3ce526b574d17abe93
curl -fsSLo /tmp/fan2go \
  https://github.com/markusressel/fan2go/releases/download/${FAN2GO_VERSION}/fan2go-linux-amd64
echo "${FAN2GO_SHA256}  /tmp/fan2go" | sha256sum -c -
install -m 0755 /tmp/fan2go /usr/local/bin/fan2go
restorecon -v /usr/local/bin/fan2go 2>/dev/null     # SELinux machines: the label systemd may run
mkdir -p /etc/fan2go /var/lib/fan2go
fan2go detect                       # lists the hwmon platform and the NVIDIA devices by PCI address
```

Use the `fan2go-linux-amd64` build, not the `-no-nvml` build: the NVML build reads the
GPU temperatures itself. The digest above is the one GitHub publishes for the 0.15.0 release asset
(checked by download). A newer release is a deliberate change ([06](06-operations.md)),
not a download of "latest".

### Configure

`/etc/fan2go/fan2go.yaml`. Take the platform name and the NVIDIA device names from
`fan2go detect`; the device name holds the GPU's PCI bus (`nvidia-10DE2BB5-0100` is
the GPU at `01:00.0`), so it stays the same across reboots.

```yaml
# GPU airflow fans for passive GPUs.
# Fans are PSU-powered; the headers carry only PWM and tach, so every duty is safe.
dbPath: "/var/lib/fan2go/fan2go.db"

fanController:
  adjustmentTickRate: 1000ms

fans:
  - id: gpu_fan_a
    hwmon:
      platform: nct6799-isa-0290       # from fan2go detect
      rpmChannel: 4                    # S2 standard: GPU fan A on channel 4, GPU fan B on 6
      pwmChannel: 4
    neverStop: true
    curve: gpu_airflow_curve
    controlMode:
      onExit:                          # fan2go stops: manual mode, full speed
        mode: pwm
        speed: 255
  - id: gpu_fan_b
    hwmon:
      platform: nct6799-isa-0290
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
      device: nvidia-10DE2BB5-0100     # from fan2go detect
      index: 1
  - id: gpu1_temp
    nvidia:
      device: nvidia-10DE2BB5-0300
      index: 1
  - id: cpu_temp
    hwmon:
      platform: k10temp-pci-00c3       # from fan2go detect; asusec-isa-0000 where asus_ec_sensors loads (see above)
      index: 1

curves:
  # The hottest GPU decides; the CPU keeps a floor of airflow.
  - id: gpu_airflow_curve
    function:
      type: maximum
      curves:
        - gpu0_curve
        - gpu1_curve
        - cpu_assist_curve
  - id: gpu0_curve
    linear:
      sensor: gpu0_temp
      steps:
        - 40: 20%
        - 55: 45%
        - 65: 70%
        - 75: 90%
        - 82: 100%
  - id: gpu1_curve
    linear:
      sensor: gpu1_temp
      steps:
        - 40: 20%
        - 55: 45%
        - 65: 70%
        - 75: 90%
        - 82: 100%
  - id: cpu_assist_curve
    linear:
      sensor: cpu_temp
      steps:
        - 60: 20%
        - 75: 40%

logging:
  level: info
```

The `controlMode.onExit` block replaces fan2go's default (`restore`): that hands the
fans back to the firmware curve, which follows the CPU only, so passive GPUs under load
would lose their airflow whenever fan2go stops. `mode: pwm` keeps the channel in manual mode, so the firmware cannot
take the speed back, whatever mode the channel had before fan2go started. Full speed
is loud and safe.

One fan line per fan and one GPU curve per GPU: a machine with one GPU drops `gpu1`.

### Service

```sh
cat > /etc/systemd/system/fan2go.service <<'EOF'
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
EOF
systemctl daemon-reload
systemctl enable --now fan2go
journalctl -u fan2go -f      # first start measures each fan's PWM-to-RPM curve; let it finish
```

The first start runs each fan through its range to measure it and stores the result
in `/var/lib/fan2go/fan2go.db`. Do it with the GPUs idle. After a fan is replaced,
stop fan2go, delete the database and start it again.

### Power limit and cooling

The fan curve and the power limit from Phase 3 ("Power limit") are a matched pair. On
an S2, two GPUs at 500 W each held 76 to 78 C with the fans at 94 percent duty,
chassis closed. At the stock 600 W the fans have no headroom left. A
higher limit needs a new load test below.

### Verify under load

With the chassis closed, run both GPUs at full load for 10 minutes (any GPU burn
container, or the largest model this machine will serve under a load test) and watch:

```sh
watch -n 5 'nvidia-smi --query-gpu=index,temperature.gpu,power.draw,clocks_event_reasons.active --format=csv,noheader;
  H=$(grep -l "^nct67" /sys/class/hwmon/hwmon*/name | xargs dirname);
  for c in $(grep -oP "rpmChannel: \K[0-9]+" /etc/fan2go/fan2go.yaml); do
    echo "fan$c: $(cat $H/fan${c}_input) rpm, pwm $(cat $H/pwm$c)"; done'
```

The loop reads the channels from the fan2go configuration, so it shows the GPU fans of
this machine: `fan4` and `fan6` on an S2.

Pass: the temperature levels off below 80 C, the fans ramp with it, and the GPU reports
no thermal slowdown. Then stop the load: the fans must come back down within about a
minute. Also test the failure path once: `systemctl stop fan2go` must send both fans
to full speed; start it again after.

The control plane's `GpuThermalRampRateHigh` alert catches a fan that fails later: a
GPU above 70 C that keeps rising more than 2 C per minute.

### S2 reference values

The S2 standard, tested with the parts of [01 BOM](01-bom.md) on Rocky Linux 10.2
(kernel 6.12) and Ubuntu 24.04 (kernel 6.17).

| Item | Value |
|---|---|
| Fan sensor chip | `nct6799` (module `nct6775`), fan2go platform `nct6799-isa-0290` |
| GPU fan A | `fan4` / `pwm4` |
| GPU fan B | `fan6` / `pwm6` |
| CPU fan | `fan2`, firmware curve |
| Rear fans (2x Arctic P8 Max) | On two of `fan1`, `fan3`, `fan5`, `fan7`, firmware curve; channels not yet recorded |
| CPU temperature for fan2go | `k10temp-pci-00c3`, index 1 (`Tctl`); on kernel 6.17 or later `asusec-isa-0000`, index 1, also works |
| GPU devices for fan2go | `nvidia-10DE2BB5-0100`, `nvidia-10DE2BB5-0300` |
| Power limit | 500 W per GPU (Phase 3, "Power limit") |
| Result | 76 to 78 C at 2x 500 W for 10 minutes, fans at 94 percent duty, chassis closed |

Every S2 is wired to channels 4 and 6 ([02](02-assembly.md), "GPU fans").

The CPU reaches 84 to 85 C during a GPU burn, from the burn's own submit threads, not
from GPU heat ([260720](learnings/260720-gpu-fan-hub-alphacool-es-guardian.md)).
This is inside the Ryzen limit (95 C). The firmware's CPU fan curve stays slow at that
temperature; set a steeper CPU fan curve in the BIOS.

## Phase 7: network and time

### Two ports, one address: an active-backup bond

A machine with two Ethernet ports runs both as one bond in `active-backup` mode: one
IP address, one default route; one port carries the traffic and the other takes over
within a fraction of a second when its link goes down. It needs nothing from the
switch, so it works on an unmanaged switch and across two separate switches. LACP
(802.3ad) is not used: it needs a configured LAG on the switch.

Two rules:

- **Match ports by MAC address, never by name.** Interface names follow the PCIe
  layout: adding, moving or removing a GPU or the IPMI card renumbers the bus and
  renames the ports (for example `enp12s0` becomes `enp14s0`, [03](03-bring-up.md)),
  and a configuration keyed by name leaves the machine without network.
- **Match the members by MAC in `ethernets`, and name them in the bond.** Members of
  an active-backup bond share the bond's MAC at runtime, so a bond that matches its
  members by MAC directly breaks on re-apply with netplan before 1.1.1
  ([LP #2065870](https://bugs.launchpad.net/netplan/+bug/2065870)); Ubuntu 24.04
  ships netplan 1.0.

Use the burned-in MAC of each port (`ethtool -P <port>`, the "Permanent address").
On a running bond, `/sys/class/net/<port>/address` shows the bond's MAC instead.
Both distributions give the ports names of their own (`lan10g`, `lan2g5`), matched by
MAC, so a GPU change can never rename them again, and the bond names its primary port
by that name.

```sh
ip -br link                                      # the ports and their current names
for p in $(ls /sys/class/net | grep -E '^en'); do echo "$p $(ethtool -P $p) $(basename $(readlink /sys/class/net/$p/device/driver))"; done
```

The list also shows a third port: the IPMI card's USB network link, through the
card's internal USB cable (a `u` in its name, for example `enp15s0u8u3c2`). It is
not a network port and never goes into the bond. See "The IPMI card's USB link" below.

**Ubuntu 24.04 (netplan):** `/etc/netplan/50-inference-node.yaml`, mode 0600 (netplan
refuses world-readable files). Remove the installer's own file (`/etc/netplan/50-cloud-init.yaml` or
`00-installer-config.yaml`) in the same step, so the ports are not configured twice:

```yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    lan10g:                          # 10 GbE, Marvell AQtion (driver atlantic)
      match:
        macaddress: "aa:bb:cc:dd:ee:01"
      set-name: lan10g
      dhcp4: false
      dhcp6: false
      optional: true                 # a dead member never blocks the boot
    lan2g5:                          # 2.5 GbE, Intel I226-V (driver igc)
      match:
        macaddress: "aa:bb:cc:dd:ee:02"
      set-name: lan2g5
      dhcp4: false
      dhcp6: false
      optional: true
  bonds:
    bond0:
      interfaces: [lan10g, lan2g5]
      parameters:
        mode: active-backup
        primary: lan10g              # the faster port carries the traffic when it is up
        mii-monitor-interval: 100
      addresses: [<host address>/24]
      routes:
        - to: default
          via: <gateway>
      nameservers:
        addresses: [<dns server>]
```

`set-name` gives the ports their own names. With a single port, keep the same
`ethernets` entry with the address on it and leave `bonds` out.

Apply it from the BMC's remote console ([03](03-bring-up.md)), not over SSH: the SSH session moves
to the new interface and drops. `netplan try` rolls back on its own unless the change
is confirmed within 120 seconds:

```sh
chmod 600 /etc/netplan/50-inference-node.yaml
netplan generate                                 # syntax check, changes nothing
netplan try                                      # confirm with Enter once the address answers
```

**Rocky Linux 10 (NetworkManager):** a systemd link file per port gives it its name,
matched by the permanent MAC
([Red Hat, interface naming](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/10/html/configuring_and_managing_networking/implementing-consistent-network-interface-naming));
NetworkManager profiles then build the bond on those names. The names apply at the
next boot, so the change is one reboot, made from the BMC's remote console. Keep the
installer's profiles first; they are the way back.

```sh
cp -a /etc/NetworkManager/system-connections /root/nm-connections-before-bond
cat > /etc/systemd/network/10-lan10g.link <<'EOF'
[Match]
PermanentMACAddress=aa:bb:cc:dd:ee:01
[Link]
Name=lan10g
EOF
cat > /etc/systemd/network/10-lan2g5.link <<'EOF'
[Match]
PermanentMACAddress=aa:bb:cc:dd:ee:02
[Link]
Name=lan2g5
EOF
dracut -f --regenerate-all

nmcli connection add type bond con-name bond0 ifname bond0 \
  bond.options "mode=active-backup,primary=lan10g,miimon=100" \
  ipv4.method manual ipv4.addresses <host address>/24 \
  ipv4.gateway <gateway> ipv4.dns <dns server> ipv6.method disabled
nmcli connection add type ethernet port-type bond controller bond0 \
  con-name lan10g ifname lan10g ethernet.mac-address aa:bb:cc:dd:ee:01
nmcli connection add type ethernet port-type bond controller bond0 \
  con-name lan2g5 ifname lan2g5 ethernet.mac-address aa:bb:cc:dd:ee:02
nmcli -f NAME,DEVICE connection show                # the installer's profiles
nmcli connection delete <each installer profile of the two ports>
reboot
```

The way back, from the BMC console: restore `/root/nm-connections-before-bond` into
`/etc/NetworkManager/system-connections`, delete the bond's three profiles and the two
link files, run `dracut -f --regenerate-all`, reboot.

On both distributions, check, and test the failover once by pulling each cable in turn
while a ping runs from another machine:

```sh
ip -br addr show bond0                           # the address on bond0
grep -E 'Currently Active Slave|MII Status|Slave Interface' /proc/net/bonding/bond0
ping -c 3 <gateway>
```

A ping loses at most a packet or two per switchover. Both ports must show
`MII Status: up` when cabled: a standby port that is down without anyone noticing is
no redundancy at all, so look at `/proc/net/bonding/bond0` after every visit to the
rack. The inference node and Docker need nothing for the bond: Docker's networks use
the default route, whichever port carries it.

### The IPMI card's USB link

The card's internal USB cable gives the host a small network link to the card: ASUS's
Linux firmware update tool talks to the card over it, with the card at `169.254.0.17`
([ASUS FAQ](https://www.asus.com/support/faq/1047906/)). Left alone, the installer's
profile tries DHCP on it at every boot. Give it a fixed link-local address and no
route, so it can never carry the default route or delay the boot. Match it by its MAC,
like the bond's ports: its name changes when the PCIe layout changes.

```sh
ip -br link | grep -E '^en[^ ]*u[0-9]'            # the card's USB link, and its MAC
```

**Ubuntu 24.04:** in `/etc/netplan/50-inference-node.yaml`, under `ethernets`:

```yaml
    bmc-usb:                         # IPMI card's USB link: no route, no DNS
      match:
        macaddress: "aa:bb:cc:dd:ee:03"
      addresses: [169.254.0.18/16]
      dhcp4: false
      dhcp6: false
      link-local: []
      optional: true
```

**Rocky Linux 10:**

```sh
nmcli -f NAME,DEVICE connection show                 # the installer's profile of the link
nmcli connection delete <that profile>
nmcli connection add type ethernet con-name bmc-usb ethernet.mac-address aa:bb:cc:dd:ee:03 \
  ipv4.method manual ipv4.addresses 169.254.0.18/16 ipv4.never-default yes \
  ipv6.method disabled connection.autoconnect yes
```

Check: `ping -c 2 169.254.0.17` answers, and `ip route` shows the default route on
`bond0` only.

### Firewall and time

- The inference node opens every connection itself, to the control plane's inference
  port (443 unless the install command names another). The machine needs no inbound
  port but SSH.
- If this machine also runs the control plane, open 443 (inference port) and 3443
  (control plane port, limit it to the administrators' networks).
- The clock must be right: every connection between the planes is mutual TLS with
  certificates that have a start and an end time.

```sh
timedatectl set-ntp true && timedatectl     # "System clock synchronized: yes"

# Ubuntu 24.04
ufw allow OpenSSH && ufw --force enable      # plus 443/tcp and 3443/tcp on a control-plane machine

# Rocky Linux 10: firewalld is on; take the web console out, keep SSH
systemctl disable --now cockpit.socket
firewall-cmd --permanent --remove-service=cockpit
firewall-cmd --permanent --add-service=ssh   # plus --add-port=443/tcp --add-port=3443/tcp on a control-plane machine
firewall-cmd --reload
```
