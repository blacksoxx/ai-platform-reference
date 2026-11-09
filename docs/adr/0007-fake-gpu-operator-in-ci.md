# ADR 0007: Simulated GPUs in ci with the Run:ai fake GPU operator

**Status**: accepted, 2026-11-09

## Context

Every change must prove that the platform still bootstraps and still schedules a GPU job,
on a laptop and on a GitHub runner, neither of which has a GPU. Options: skip GPU scheduling
in ci; a cloud GPU runner per run; a device plugin that advertises GPUs that do not exist.

## Decision

The Run:ai fake-gpu-operator (`platform/fake-gpu-operator`, ci only) runs on kind workers
labelled `run.ai/simulated-gpu-node-pool=default` and advertises two `nvidia.com/gpu` per
worker, injects a fake `nvidia-smi` into GPU Pods and serves DCGM-style metrics on a Service
named like the real exporter. A ServiceMonitor scrapes it, so the same dashboard, the same
alert rules and the same KAI queues work in ci and in the lab. The kind nodes carry the
platform's vendor label so overlays select them exactly as they select the Spark.

## Consequences

- Scheduling, quotas, queue limits, dashboards and alerts are exercised on every run with
  real Kubernetes objects; only the kernel driver is missing.
- A GPU Pod in ci sees a fake `nvidia-smi`; code that needs CUDA cannot run there. The
  inference backend in ci is llama.cpp on CPU for that reason (ADR 0010).
- The operator must not coexist with the real GPU Operator in one cluster; it is only in
  `apps/ci`.
