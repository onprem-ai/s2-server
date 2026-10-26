# NVIDIA driver/library version mismatch after an upgrade without reboot

Date: 2026-05-21
OS: Ubuntu 24.04 (kernel 6.17), NVIDIA driver 595.58.03 → 595.71.05 (open kernel modules)

**Summary.** Ubuntu's `unattended-upgrades` upgraded all NVIDIA packages from 595.58.03 to 595.71.05. DKMS rebuilt the kernel module on disk, but the old module stayed loaded because nothing rebooted the machine. The NVIDIA Container Toolkit refuses to start a GPU container when the loaded kernel module and the userspace library differ. For about 8 hours every GPU container was refused with `driver/library version mismatch`. Fix: reboot. Lesson: driver upgrades must be deliberate and followed by a reboot, never unattended.

## Symptoms

1. The inference container never starts. It fails at start (not OOM, not an application crash) and has no application logs.
2. The container runtime reports a prestart hook failure:
   ```
   nvidia-container-cli.real: initialization error: nvml error: driver/library version mismatch
   ```
3. `nvidia-smi` on the host fails too:
   ```
   Failed to initialize NVML: Driver/library version mismatch
   NVML library version: 595.71
   ```
4. Image and container configuration are correct. The problem is in the host driver.

## Diagnosis

```bash
# Kernel module loaded in memory since the last boot
cat /proc/driver/nvidia/version
# → 595.58.03

# Kernel module installed on disk
modinfo nvidia | head -5
# → 595.71.05
```

These must match exactly. Even a patch-level difference is a hard failure.

`/var/log/apt/history.log` showed the trigger:

```
Start-Date: 2026-05-21  06:53:56
Commandline: /usr/bin/unattended-upgrade
Upgrade: libnvidia-common-595 (595.58.03 → 595.71.05), nvidia-dkms-595-open (595.58.03 → 595.71.05), ... [15 packages total]
```

## What happened

1. The driver was installed with `apt-get install -y nvidia-driver-590-open`. APT resolved this to 595.58.03 packages (the 590 metapackage pulled 595 dependencies). No holds or pins were set.
2. `unattended-upgrades` found 595.71.05 in the `noble-security` pocket and upgraded all 15 NVIDIA packages. DKMS rebuilt the module on disk.
3. The running kernel kept the old 595.58.03 module. No reboot happened.
4. About 8 hours later a GPU container was started. The NVIDIA container runtime hook detected the mismatch and refused it.
5. The old 590 metapackages were also still installed.

## Fix

### Immediate: reboot

A reboot loads the 595.71.05 module from disk and ends the mismatch.

### Prevent: hold driver, kernel and CUDA packages

Keep `unattended-upgrades` enabled for OS security patches (glibc, openssl, openssh, ...), but exclude everything that needs a coordinated reboot.

1. Hold all NVIDIA packages:

   ```bash
   sudo apt-mark hold nvidia-driver-595-open nvidia-dkms-595-open \
     nvidia-kernel-source-595-open nvidia-kernel-common-595 \
     libnvidia-compute-595 libnvidia-gl-595 nvidia-utils-595 \
     libnvidia-cfg1-595 libnvidia-common-595 libnvidia-decode-595 \
     libnvidia-encode-595 libnvidia-extra-595 libnvidia-fbc1-595 \
     nvidia-compute-utils-595 nvidia-firmware-595-595.71.05 \
     nvidia-settings xserver-xorg-video-nvidia-595
   ```

2. Hold the kernel packages, including the HWE metapackages. Otherwise APT pulls new `linux-image-*` versions through the metapackage. A new kernel triggers a DKMS rebuild that can fail and leave the machine without a GPU driver.

   ```bash
   sudo apt-mark hold "linux-image-$(uname -r)" "linux-headers-$(uname -r)" \
     linux-image-generic-hwe-24.04 linux-headers-generic-hwe-24.04
   ```

3. As a second layer, add to the `Package-Blacklist` section of `/etc/apt/apt.conf.d/50unattended-upgrades`:

   ```
       "nvidia-.*";
       "libnvidia-.*";
       "linux-image-.*";
       "linux-headers-.*";
       "cuda-.*";
   ```

   This still works if a hold is removed by accident.

4. Purge old driver generations, so only one is installed:

   ```bash
   sudo apt purge nvidia-dkms-590-open nvidia-driver-590-open
   ```

### Planned upgrade procedure

```bash
# 1. Release the holds
sudo apt-mark unhold 'nvidia-*' 'libnvidia-*' 'linux-image-*' 'linux-headers-*'

# 2. Upgrade
sudo apt update && sudo apt upgrade

# 3. Reboot (required for the new kernel module and kernel)
sudo reboot

# 4. Verify
nvidia-smi
cat /proc/driver/nvidia/version
uname -r

# 5. Hold again
sudo apt-mark hold 'nvidia-*' 'libnvidia-*' 'linux-image-*' 'linux-headers-*'
```

## Version context

| Version | Release | Changes |
|---------|---------|---------|
| 595.58.03 | 2026-03-24 | First stable R595: DRI3 v1.2, `modeset=1` default, Vulkan extensions, VRAM-to-RAM fallback |
| 595.71.05 | 2026-04-28 | Patch: OpenGL suspend/resume fix (Wayland), Fabric Manager crash detection, device memory leak fix |

A minor patch in the same branch was enough to block all GPU containers.

## Lessons

1. NVIDIA driver upgrades must be deliberate and followed by a reboot, never unattended. A loaded kernel module cannot be replaced at runtime.
2. Kernel upgrades are just as risky: they trigger a DKMS rebuild of the NVIDIA module.
3. Do not disable `unattended-upgrades`; exclude driver, kernel and CUDA packages from it.
4. Use two layers: `apt-mark hold` and the `unattended-upgrades` blacklist.

## References

- [NVIDIA Driver Installation Guide: Version Locking](https://docs.nvidia.com/datacenter/tesla/driver-installation-guide/version-locking.html)
- [Stop NVIDIA Drivers from Breaking: A GPU Server Guide (Ubuntu)](https://www.gpu-mart.com/blog/stop-nvidia-drivers-from-breaking-on-ubuntu)
- [Ubuntu "unattended-upgrades" for CUDA drivers (NVIDIA Forums)](https://forums.developer.nvidia.com/t/ubuntu-unattended-upgrades-for-cuda-drivers/332449)
- [Disabling unattended upgrades of CUDA toolkit (Ateliere)](https://help.ateliere.com/live/docs/installation/base-platform/unattended-upgrades/)
- [NVIDIA Driver Installation Best Practices (Exxact)](https://support.exxactcorp.com/hc/en-us/articles/33236574432023-NVIDIA-Driver-Installation-Best-Practices-Guide)
