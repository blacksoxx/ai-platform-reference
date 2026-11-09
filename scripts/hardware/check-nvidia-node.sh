#!/bin/sh
# NVIDIA node check: prove that a container on the node sees the GPU (written for the DGX Spark).
#
# What runs on the Spark, every container with --rm so none is left behind:
#   1. our arm64 gpu-probe image without a GPU request, to show the difference
#   2. the same image with --gpus all: nvidia-smi appears inside the container
#   3. the CUDA vectorAdd sample from the GPU Operator docs
# Every image this script loaded or pulled is removed at the end, so the shared
# company machine is left as it was found. Nothing is installed on the host.
#
# Usage: scripts/hardware/check-nvidia-node.sh [ssh-host]      default host: sparky
# Needs: the probe image built locally (make image-gpu-probe) and ssh access.
set -eu

HOST=${1:-sparky}
PROBE_IMAGE=${GPU_PROBE_IMAGE:-ai-platform-reference/gpu-probe:dev}
# From the NVIDIA GPU Operator docs, "Verification: Running Sample GPU Applications",
# https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/latest/getting-started.html
# The tag has linux/amd64 and linux/arm64 variants (docker buildx imagetools inspect, 2026-11-09).
CUDA_SAMPLE=nvcr.io/nvidia/k8s/cuda-sample:vectoradd-cuda12.5.0-ubuntu22.04

remote() { ssh -o BatchMode=yes "$HOST" "$@"; }
have_image() { if remote "docker image inspect $1 >/dev/null 2>&1"; then echo yes; else echo no; fi; }

# Remember what was already there so cleanup removes only what this script added.
had_probe=$(have_image "$PROBE_IMAGE")
had_sample=$(have_image "$CUDA_SAMPLE")

cleanup() {
  echo "--- cleanup on $HOST"
  if [ "$had_probe" = no ]; then remote "docker image rm -f $PROBE_IMAGE >/dev/null 2>&1 || true"; fi
  if [ "$had_sample" = no ]; then remote "docker image rm -f $CUDA_SAMPLE >/dev/null 2>&1 || true"; fi
  echo "probe image present: $(have_image "$PROBE_IMAGE") (before this run: $had_probe)"
  echo "cuda sample present: $(have_image "$CUDA_SAMPLE") (before this run: $had_sample)"
}
trap cleanup EXIT

echo "--- host $HOST"
remote 'echo "arch=$(uname -m) kernel=$(uname -r)"; nvidia-smi --query-gpu=name,driver_version --format=csv,noheader'

echo "--- ship the arm64 probe image (docker save | docker load, no registry involved)"
docker save --platform linux/arm64 "$PROBE_IMAGE" | remote 'docker load'

echo "--- 1. probe without a GPU request"
remote "docker run --rm $PROBE_IMAGE"

echo "--- 2. probe with --gpus all"
# NVIDIA Container Toolkit docs, "Running a Sample Workload with Docker",
# https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/sample-workload.html
# show: docker run --rm --runtime=nvidia --gpus all ubuntu nvidia-smi
# DGX OS does not register a "nvidia" runtime in Docker (docker info lists runc only).
# --gpus all works on its own because dockerd finds /usr/bin/nvidia-container-runtime-hook.
remote "docker run --rm --gpus all $PROBE_IMAGE"

echo "--- 3. CUDA vectorAdd sample"
remote "docker run --rm --gpus all $CUDA_SAMPLE"
