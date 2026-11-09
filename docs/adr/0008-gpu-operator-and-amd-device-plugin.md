# ADR 0008: NVIDIA GPU Operator without driver and toolkit; AMD device plugin, not the AMD operator

**Status**: accepted, 2026-11-09

## Context

The NVIDIA node is a DGX Spark running DGX OS, which ships the driver and the NVIDIA
Container Toolkit; the AMD node is a Ryzen AI Max+ APU. The NVIDIA GPU Operator can install
driver and toolkit itself; the AMD GPU Operator targets Instinct accelerators and AMD's
Radeon and Ryzen documentation lists the Ryzen AI Max 300 series as supported on Linux with
PyTorch only.

## Decision

NVIDIA: the GPU Operator (`platform/nvidia-gpu-operator`, lab only) with `driver.enabled=false`
and `toolkit.enabled=false`, as its documentation prescribes for pre-installed drivers and
toolkit, CDI on, DCGM exporter with a ServiceMonitor, node status exporter on. AMD: the ROCm
Kubernetes device plugin with its node labeller and the ROCm device metrics exporter
(`platform/amd-device-plugin`, `platform/amd-metrics-exporter`, lab only), installed directly
on the AMD node. GPU nodes carry a vendor label and taint set at join time (RKE2 agent config).

## Consequences

- DGX OS keeps ownership of the driver and the toolkit; the operator never tries to replace a
  vendor-tuned stack. RKE2's own containerd must know the NVIDIA runtime: that is verified on
  the hardware (setup-lab.md) and, if needed, the toolkit component is enabled with RKE2's
  containerd socket.
- AMD scheduling works with `amd.com/gpu`; the richer features of the AMD GPU Operator
  (driver management, device configuration) are not available for the APU and not needed.
- Two vendors, two metric families: DCGM for NVIDIA, the ROCm exporter for AMD; the
  dashboards and alerts name both.
