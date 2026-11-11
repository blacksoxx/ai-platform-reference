#!/bin/sh
# gpu-probe: print what this container can see.
#
# It proves one image runs on arm64 and amd64, and it is the
# body of the sample GPU jobs: the same image reports an NVIDIA GPU on the
# Spark, AMD device nodes on the Halo, and nothing in ci, where the fake GPU
# operator advertises GPUs to the scheduler without exposing a device.
set -u

echo "arch:     $(uname -m)"
echo "kernel:   $(uname -r)"
echo "hostname: $(hostname)"
if [ -r /etc/os-release ]; then
  . /etc/os-release
  echo "image os: ${PRETTY_NAME:-unknown}"
fi
echo "user:     $(id -u):$(id -g)"

echo "--- nvidia"
# When a GPU is requested, the NVIDIA Container Toolkit mounts the host's
# nvidia-smi and driver libraries into the container and sets
# NVIDIA_VISIBLE_DEVICES. Without a request none of that is present.
echo "NVIDIA_VISIBLE_DEVICES=${NVIDIA_VISIBLE_DEVICES:-<unset>}"
if command -v nvidia-smi >/dev/null 2>&1; then
  # The real nvidia-smi answers the query; the one the fake GPU operator injects on ci only
  # prints its table, so fall back to that.
  nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader 2>/dev/null \
    || nvidia-smi 2>&1 | head -20 \
    || echo "nvidia-smi: present but exited $?"
else
  echo "nvidia-smi: not in this container (no NVIDIA GPU injected)"
fi

echo "--- amd"
# ROCm needs the kernel driver node /dev/kfd and a render node under /dev/dri.
# The AMD device plugin mounts them into the pod; nothing else is injected.
if [ -e /dev/kfd ]; then echo "/dev/kfd: present"; else echo "/dev/kfd: absent"; fi
if [ -d /dev/dri ]; then
  echo "/dev/dri: $(ls /dev/dri | tr '\n' ' ')"
else
  echo "/dev/dri: absent"
fi
