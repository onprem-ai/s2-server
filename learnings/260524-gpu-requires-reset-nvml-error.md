# GPU "requires reset" NVML error blocks container start

Date: 2026-05-24
Hardware: NVIDIA RTX PRO 6000 Blackwell Workstation Edition (96 GB)
Driver: NVIDIA 595.71.05 / CUDA 13.2

**Summary.** The GPU entered a fault state in which NVML reports `gpu requires reset`. The NVIDIA container runtime then refused to give the GPU to any container, so the inference container failed at start with no application logs. The trigger is unknown. Fix: `nvidia-smi --gpu-reset -i <index>` when no process uses the GPU; if that fails, reboot.

## Symptoms

- The inference container fails at start and restarts in a loop. It is not OOM and not an application error.
- No application logs at all: the container never started.
- `nvidia-smi` shows the GPU in a degraded state:
  - Fan speed: `ERR!`
  - Power draw: `N/A / N/A`
  - MIG mode: `ERR!`
  - ECC errors: `[N/A]`
  - GPU utilization: `N/A`
  - Memory usage: `0 MiB`, no processes
- The container runtime error:

```
OCI runtime create failed: runc create failed: unable to start container process:
error during container init: error running prestart hook #0: exit status 1, stdout: , stderr:
nvidia-container-cli.real: detection error: nvml error: gpu requires reset: unknown
```

## Root cause

The GPU went into a fault state that sets the NVML "reset required" flag. Possible triggers are ECC error accumulation, a power event, a PCIe error or a driver bug; the actual one is unknown. With the flag set:

1. `nvidia-container-cli` (the OCI prestart hook) queries NVML.
2. NVML returns `gpu requires reset`.
3. The hook exits with status 1 and `runc` aborts the container start.

This looks like an ordinary crash loop. Only the start error of the container shows the real cause; the error is not in the application logs.

`pci=noaer` (see [260211-ssh-hang-pcie-gpu-errors.md](260211-ssh-hang-pcie-gpu-errors.md)) does not prevent this NVML-level fault.

## Fix

In order of invasiveness:

1. Stop everything that uses the GPU, then reset it:
   ```bash
   nvidia-smi --gpu-reset -i <index>
   ```
   This needs no process on the GPU. It may not work in a severe fault state.
2. Reboot the machine.

After recovery, containers start normally. Image and configuration were fine.

## Verify and detect

```bash
# Direct check: does the GPU need a reset?
nvidia-smi --query-gpu=reset_status.reset_required --format=csv,noheader

# Xid errors often come before a fault
sudo dmesg | grep -i xid
```

Signals worth monitoring:

| Signal | Source | Meaning |
|--------|--------|---------|
| `ERR!` for fan / power / MIG | `nvidia-smi` | GPU in fault state |
| `reset_status.reset_required` | `nvidia-smi --query-gpu` | GPU needs a reset (works even when DCGM is down) |
| Exporter returns no metrics | DCGM Exporter | GPU or DCGM failed |
| `DCGM_FI_DEV_XID_ERRORS` increases | DCGM Exporter | Xid error, early warning |
| `DCGM_FI_DEV_ROW_REMAP_FAILURE` | DCGM Exporter | Memory row remap failed |
| Container start error mentioning `nvidia-container-cli` | Docker events / container status | GPU not available to containers |
