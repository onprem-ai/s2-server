# 05 Acceptance: burn-in, host checks, handoff

The last step before the onprem.ai platform: prove the hardware under load while parts
can still be returned, check every setting of [04 Provisioning](04-provisioning.md)
after a reboot, and record the machine. A machine that passes every check here is ready
for the platform install.

## 1. Burn-in

Run each test with the chassis closed, in its final place. A failure here is a hardware
question first: reseat, swap, or return the part (see [01 BOM](01-bom.md)).

Order:

1. **Attended, short:** GPU thermal (10 minutes), disk health (`smartctl`), power loss,
   BMC power cycle, network failover, the host checks of section 2. Plus a **short
   run of every long test**, so it is known to start and pass before nobody watches:
   `memtester 1G 1` (about a minute), gpu-burn for 60 seconds, the `fio` job on 1 GB.
2. **Unattended, long**, one after the other in one script with a log per test:
   memory (one full pass over the free RAM, 1 to 2 hours), disk `fio` write and read
   on the full job, GPU stability (gpu-burn, 1 hour). Read the logs afterwards; a
   machine left alone must not be at the console's lock screen or in a `sudo` prompt.

Long tests that fail early in their short run are fixed first: an unattended run that
dies after one minute costs the whole night.

| Test | How | Pass |
|---|---|---|
| Memory | MemTest86 (USB, through the BMC virtual media) or `memtester` for one full pass, before EXPO is turned on | No errors. Only then EXPO ([03](03-bring-up.md), S2 values) and a second pass |
| GPU thermal | Both GPUs at full load for 10 minutes ([04](04-provisioning.md) Phase 6, "Verify under load") | Below 80 C, no thermal slowdown, fans ramp up and back down; `systemctl stop fan2go` sends both fans to full speed |
| GPU stability | The GPU burn container below on both GPUs for 1 hour | No Xid in `dmesg`, both GPUs still listed, no `AER:` lines |
| Disks | `smartctl -a /dev/nvme0` and `/dev/nvme1`; a `fio` write and read pass on the mirror (TODO: exact job) | No media errors on either disk; the mirror fully synced (`/proc/mdstat` all `[UU]`) before the test |
| Power loss | Pull the power cord while idle, plug it back in | The machine powers on by itself (BIOS "Restore AC power loss") and comes back with both GPUs |
| BMC | Power cycle through the BMC (`ipmitool ... chassis power cycle`), remote console during POST | The machine comes back; POST visible on the remote console |
| Network failover | Pull each cable in turn during a ping ([04](04-provisioning.md) Phase 7) | At most a packet or two lost |

### GPU load: gpu-burn

[gpu-burn](https://github.com/wilicc/gpu-burn) loads every GPU with matrix
multiplications and checks the results. Build it for the GPU's architecture
(Blackwell RTX PRO: compute capability 12.0, `COMPUTE=120`, CUDA 12.8 or later); the
default build (7.5) does not run on Blackwell.

```sh
git clone https://github.com/wilicc/gpu-burn /tmp/gpu-burn && cd /tmp/gpu-burn
docker build --build-arg CUDA_VERSION=12.8.1 --build-arg IMAGE_DISTRO=ubuntu24.04 \
  --build-arg COMPUTE=120 -t gpu-burn:local .
# --entrypoint: the NVIDIA base image's entrypoint script passes the arguments to
# `exec`, which takes -tc as its own option ("exec: -t: invalid option").
docker run --rm --gpus all --entrypoint /app/gpu_burn gpu-burn:local -tc 600    # 10 min; 3600 for 1 h
```

`-tc` uses the tensor cores, the load inference puts on the GPU. Watch temperatures and
fans in a second shell with the loop from [04](04-provisioning.md) Phase 6, "Verify under
load". gpu-burn ends with `OK` or `FAULTY` per GPU; `FAULTY` fails the test.

## 2. Reboot and verify the host

Reboot once. Kernel parameters, the module blacklist and the driver only take effect
at boot.

```sh
reboot
```

Then every check below must pass before the platform is installed (section 4). Run
them with [scripts/host-checks.sh](scripts/host-checks.sh), **as root**: it prints PASS
or FAIL per check with the value it saw, never waits for input, and exits with the
number of failures.

```sh
sudo bash host-checks.sh        # "ALL PASSED", or the FAIL lines to fix
```

Run as another user, several checks read the wrong state and give false alarms or
false passes: `dnf` uses that user's own cache and asks to import repository keys that
root already has, `dmesg`, `sshd -T`, `firewall-cmd` and the Docker socket are refused.
The script refuses to run without root for that reason.

What it checks, for reference:

```sh
cat /proc/cmdline                                         # pcie_aspm=off pcie_port_pm=off iommu=pt
grep -E 'Currently Active Slave|MII Status' /proc/net/bonding/bond0   # two-port machines: both members up (04 Phase 7)
lsmod | grep -c nouveau                                   # 0
apt-mark showhold                                         # Ubuntu 24.04: the kernel packages (04 Phase 3)
dnf versionlock list                                      # Rocky Linux 10: kernel, NVIDIA branch, Docker (04 Phases 3, 5)
systemctl is-enabled dnf-automatic.timer                  # Rocky Linux 10: enabled (04 Phase 2)
grep -E '^(upgrade_type|apply_updates|reboot) *=' /etc/dnf/automatic.conf   # Rocky Linux 10: security, yes, never
apt-config dump APT::Periodic::Unattended-Upgrade         # Ubuntu 24.04: "1" (04 Phase 2)
apt-config dump Unattended-Upgrade::Package-Blacklist | grep -c nvidia   # Ubuntu 24.04: 1 or more: GPU stack excluded
getenforce                                                # Rocky Linux 10: Enforcing
grep DynamicPowerManagement: /proc/driver/nvidia/params   # 0 (04 Phase 3)
cat /proc/driver/nvidia/version                           # loaded module version ...
nvidia-smi --query-gpu=driver_version --format=csv,noheader   # ... equals the userspace version
nvidia-smi -L                                             # every GPU, by UUID
nvidia-smi --query-gpu=index,name,persistence_mode,power.limit,pcie.link.gen.max,pcie.link.width.max,pcie.link.width.current \
  --format=csv                                            # persistence Enabled, power limit 500 W (04 Phase 3), width as the slot plan says
systemctl is-active nvidia-power-limit                   # active (04 Phase 3)
systemctl is-active fan2go                                # machines with OS-controlled GPU fans (04 Phase 6)
nvidia-smi topo -m                                        # how the GPUs connect (multi-GPU)
dmesg | grep -iE 'NVRM: Xid|IO_PAGE_FAULT|AER:' | tail    # nothing
cat /proc/mdstat                                          # every array [UU], no resync running (04 Phase 1)
systemctl is-active mdmonitor                             # Rocky Linux 10: active, with MAILADDR or PROGRAM set
ip route | grep default                                   # default route on bond0 only, never the card's USB link (04 Phase 7)
sshd -T | grep -iE '^(permitrootlogin|passwordauthentication) '   # permitrootlogin no; password login yes or no as chosen (04 Phase 1)
docker version --format '{{.Server.APIVersion}}'          # 1.44 or later
docker info --format '{{json .Runtimes}}' | grep -o nvidia
docker run --rm --gpus all ubuntu:24.04 nvidia-smi -L                # through the nvidia runtime
docker run --rm --device nvidia.com/gpu=all ubuntu:24.04 nvidia-smi -L   # through CDI
```

### Does every GPU get its full PCIe bandwidth?

Each GPU must get the number of PCIe lanes the machine's slot plan gives it: x16 for
one GPU on a CPU slot, x8 each for two GPUs on a desktop platform such as the S2. A
GPU with half its lanes moves data at half the rate: model loading takes twice as
long, and a model split over several GPUs (tensor parallel) slows down at every step.
Nothing fails and nothing is logged, so only this check finds it.

```sh
for d in $(lspci -D -d 10de: | awk '/3D|VGA/{print $1}'); do
  echo "$d: x$(cat /sys/bus/pci/devices/$d/current_link_width) of x$(cat /sys/bus/pci/devices/$d/max_link_width), $(cat /sys/bus/pci/devices/$d/current_link_speed)"
done
lspci -tv | grep -iE 'nvidia|non-volatile|nvme'    # what shares the GPUs' root ports
```

Read the width (`x8`), not the speed: the speed drops to 2.5 GT/s at idle and comes
back under load, also with ASPM off (check `pcie.link.gen.current` with
`nvidia-smi` under load). The width does not change with load. A width below the slot
plan ([02](02-assembly.md#slot-plan)) has one of these causes, in order of likelihood:

1. **A disk shares the GPU's lanes.** On many desktop boards an M.2 slot takes lanes
   from a GPU slot. On the S2, an NVMe in M.2_2 drops GPU 1 from x8 to x4: move it to
   M.2_3 or M.2_4 ([slot plan](02-assembly.md#slot-plan)). The same disk then also shows up on a CPU
   root port next to the GPUs in `lspci -tv`.
2. **A BIOS setting.** PCIe bifurcation set by hand, or a slot forced to a lower mode.
3. **Seating or a riser.** A GPU not fully in its slot, or a riser cable rated for
   fewer lanes or a lower generation. Reseat it, or remove the riser.

Fix it before the machine serves anything, and read the check again after every
hardware change.

### Do the GPUs reach each other?

Multi-GPU machines: `nvidia-smi topo -p2p r` reports capability, not whether
peer-to-peer writes really arrive. The test that counts is a tensor-parallel model
starting past NCCL initialization with no `IO_PAGE_FAULT` in `dmesg`.

## 3. Record the machine

Fill in the [machine record](machine-record.md): the inventory from
[04](04-provisioning.md) Phase 1, the output of section 2, the burn-in results, and the
firmware and driver versions. For every check: who performed it and when.

## 4. Hand off: install the platform

Take the install command from the control plane: **Servers**, **Add Inference Node**.
Run it as your own user; it asks for `sudo` once:

```sh
curl -fsSL https://get.onprem.ai/node | sh -s -- \
  --control-plane-gateway-address <control plane address> \
  --control-plane-root-certificate-sha256 <fingerprint> --join-token <token>
```

A machine that becomes the control plane and an inference node at once:
`curl -fsSL https://get.onprem.ai/platform | sh`.

A GPU machine must run models in containers. Say so, so that the node reports a
fault instead of falling back to running engines as processes:

```sh
echo 'EXECUTION_CLASS=container' >> /etc/onprem-ai/inference-node.env
systemctl restart onprem-ai-inference-node
onprem-ai-node doctor --verify-containers
```

The line stays through every later install and update: the installer keeps an
existing configuration file, adds only the settings a release is missing, and never
changes a setting it did not write. Only `onprem-ai-node uninstall` removes the file.

`doctor` must report every GPU, the Docker verdict `AVAILABLE`, and the connection to
the control plane. In the control plane, the machine shows under **Servers** as
connected with its GPUs; run **Verify containers** from its menu once. The reason codes
are in the debug guide **Inference Node Container Detection**.

Then deploy one small model and one model that uses every GPU of the machine (on a
multi-GPU machine, a tensor-parallel one). The first proves the container path, the
second proves peer-to-peer.

## 5. Acceptance certificate for the customer

When every check passed, fill in the [acceptance certificate](acceptance-certificate.md)
from the record's **Acceptance** table: each check, who performed it, when, and the
result. The person who approves the machine signs it. It goes to the customer with
the machine; a copy stays with the record.
