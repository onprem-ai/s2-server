# AMD-Vi IOMMU Blocks GPU Peer-to-Peer DMA: NCCL Hang on Dual RTX PRO 6000 Blackwell

**Date:** 2026-07-18
**Hardware:** AMD Ryzen platform with AMD-Vi IOMMU, 2x NVIDIA RTX PRO 6000 Blackwell
Server Edition (96 GB), NVIDIA driver 595.71.05

## Summary

- **What happened:** a tensor-parallel (TP=2) vLLM model hung forever at NCCL start.
  Both workers ran at 100% CPU and 100% GPU with no progress.
- **Cause:** with DMA remapping (IOMMU translated mode), GPU peer-to-peer writes fault
  (`IO_PAGE_FAULT` in `dmesg`). The write is dropped, so the first NCCL collective waits
  forever for a completion that never comes.
- **Fix:** add `iommu=pt` (IOMMU passthrough) to the kernel command line and reboot.
  Passthrough keeps the IOMMU on for interrupt remapping and VFIO. It only skips DMA
  address translation for devices owned by the host, so GPU-to-GPU DMA goes through.

## Symptoms

- Multi-GPU startup freezes right after a line like `vLLM is using nccl==X.Y.Z`, or at
  the first collective (all_reduce, broadcast).
- Each worker process sits at 100% CPU. `nvidia-smi` shows 100% GPU utilization, but
  VRAM stays at about 1 GB (CUDA context only).
- No new log lines. Compile and JIT cache directories do not grow.
- `sudo dmesg | grep IO_PAGE_FAULT` shows
  `AMD-Vi: Event logged [IO_PAGE_FAULT domain=... address=... flags=...]` on a GPU PCI
  address, at the moment NCCL started.
- `nvidia-smi topo -p2p r` still reports `OK`. It reports capability, not whether the
  IOMMU lets the writes through.

## Hang or compile?

100% utilization is easy to mistake for kernel compilation.

| Signal | Compiling (healthy) | NCCL busy-wait (hung) |
|--------|---------------------|------------------------|
| Cache dirs (torchinductor, flashinfer, jit) | growing | empty |
| VRAM | grows as weights load | frozen |
| Log | prints new phase lines | frozen at NCCL init |
| `dmesg` | clean | `IO_PAGE_FAULT` entries |

## Root cause

By default AMD-Vi remaps every PCIe DMA address through I/O page tables (translated
mode). GPU peer-to-peer transfers (NCCL P2P transport, CUDA IPC) write directly to the
peer GPU's BAR addresses. Under sustained P2P traffic on this platform these writes
fault, the IOMMU logs `IO_PAGE_FAULT`, and the write is dropped. NVIDIA's NCCL
troubleshooting guide says IOMMU DMA remapping "can cause a significant performance
reduction or even a hang" for PCIe P2P on bare metal, and recommends passthrough or a
disabled IOMMU.

Public reports of the same issue:

- [NCCL P2P hang on dual RTX PRO 6000 Blackwell Workstation Edition (NVIDIA forum)](https://forums.developer.nvidia.com/t/nccl-p2p-hang-on-dual-rtx-pro-6000-blackwell-workstation-edition-wrx90e-sage-se/365048)
- [NVIDIA/nccl issue #1999](https://github.com/NVIDIA/nccl/issues/1999)
- [NCCL troubleshooting guide](https://docs.nvidia.com/deeplearning/nccl/user-guide/docs/troubleshooting/gpu_troubleshooting.html)
- [NCCL hangs on L40S GPUs, resolved via IOMMU passthrough (NVIDIA forum)](https://forums.developer.nvidia.com/t/nccl-hangs-on-l40s-gpus-pcie-resolved-via-iommu-passthrough/368169)

## Fix

1. Add `iommu=pt` to the kernel command line.
2. Reboot. The command line is read once at boot.
3. Verify:

```bash
grep -o "iommu=pt" /proc/cmdline           # parameter active
sudo dmesg | grep -c IO_PAGE_FAULT         # must stay 0 under tensor-parallel load
# then start the tensor-parallel workload; NCCL init should pass in seconds
```

## Why `iommu=pt` and not the alternatives

| Option | Verdict |
|--------|---------|
| `iommu=pt` | Chosen. The IOMMU stays on (interrupt remapping and VFIO still work). Only default DMA translation for host-owned devices is skipped. Documented fix for this failure. |
| `NCCL_P2P_DISABLE=1` | Works around NCCL only. FlashInfer all-reduce and CUDA IPC still fault. Slower tensor parallelism. |
| `amd_iommu=off` | Too much: removes interrupt remapping and VFIO. Not needed. |
| Disable IOMMU/ACS in the BIOS | Same effect, but not scriptable or reproducible. |

## Trade-offs

- Single-GPU workloads never use P2P DMA, so `iommu=pt` neither helps nor hurts them.
- DMA mapping overhead for other host devices (NVMe, NIC) goes down slightly.
- The IOMMU stays on: interrupt remapping is unchanged, and VFIO devices still get
  translated mappings.
- The cost is security only: a faulty or malicious PCIe device could DMA into host
  memory that translated mode would have blocked. This is acceptable for a
  single-tenant bare-metal server with a fixed set of devices and no hotplug or
  Thunderbolt.
- Rare chipset quirks can behave differently in passthrough mode. Run the
  verification above after every reboot onto new hardware.

## Follow-up the same day: host RAM exhausted during compile

After `iommu=pt` fixed the hang, the next start took the machine down again. This was a
memory problem, not the IOMMU (zero `IO_PAGE_FAULT` in that boot).

- NCCL init passed in seconds and the weights loaded (79.3 GiB VRAM per GPU).
- The first-start compile phase (parallel kernel builds in two tensor-parallel workers,
  plus CUDA graph capture for a very long context) used up all 32 GiB of host RAM.
- The container ran with `docker run` and no memory limit. The machine had no swap at
  the time. The out-of-memory killer never fired; the journal only showed
  "Under memory pressure, flushing caches" for 15 minutes until a manual power cycle.
- Lesson: watching the run does not help. The machine hangs faster than a person can
  react. A container without a memory limit can exhaust host RAM; every GPU container
  needs `--memory` and `--memory-swap` caps.

Mitigations on the retry (they combine):

1. `--memory=20g --memory-swap=20g` on the container. A repeat kills the container,
   not the machine.
2. `MAX_JOBS=2` in the container environment. This bounds the number of parallel
   compiler processes, the main RAM consumer. Compiling is slower but bounded.
3. A shorter maximum context and fewer concurrent sequences. This means fewer and
   smaller CUDA graphs. Both can be raised later once kernel caches are warm.

## Prevention

- `iommu=pt` belongs in the standard kernel command line, so new installs cannot
  regress.
- A multi-GPU health check should confirm `iommu=pt` in `/proc/cmdline` and zero
  `IO_PAGE_FAULT` in `dmesg`.
- When a "compiling" phase shows 100% utilization, check cache directories, VRAM and
  `dmesg` before trusting it (table above).
