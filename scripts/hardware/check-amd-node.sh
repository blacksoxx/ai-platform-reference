#!/bin/sh
# AMD node check: prove that a container on the node sees the GPU (written for the Ryzen AI Max+ "Strix Halo").
#
# STATUS: not yet run on hardware (docs/setup-lab.md, validation status).
#
# What runs on the Halo, every container with --rm so none is left behind:
#   1. our amd64 gpu-probe image without devices: /dev/kfd and /dev/dri absent
#   2. the same image with the ROCm device nodes passed through
#   3. a ROCm userland image running rocminfo and rocm-smi against the host driver
# Every image this script loaded or pulled is removed at the end, so the machine is left
# as it was found. Nothing is installed on the host.
#
# Usage: scripts/hardware/check-amd-node.sh <ssh-host>
# Needs: the probe image built locally (make image-gpu-probe) and ssh access to the node.
set -eu

HOST=${1:?usage: $0 <ssh-host>}
PROBE_IMAGE=${GPU_PROBE_IMAGE:-ai-platform-reference/gpu-probe:dev}
# ROCm on Radeon and Ryzen docs, https://rocm.docs.amd.com/projects/radeon-ryzen/en/latest/index.html :
# "This ROCm on Radeon and Ryzen documentation covers releases through 7.2.1" and the support
# table lists "Ryzen APUs (AI Max 300 Series, ...) | Linux, Windows | PyTorch". The userland
# image therefore defaults to that release. Tag checked on Docker Hub on 2026-11-09.
ROCM_IMAGE=${ROCM_IMAGE:-rocm/dev-ubuntu-24.04:7.2.1}

# Device flags from the ROCm docs, "Run Docker containers", section "Without the AMD Container
# Toolkit", https://rocm.docs.amd.com/projects/install-on-linux/en/latest/how-to/docker.html :
#   docker run -it --rm --device /dev/kfd --device /dev/dri --security-opt seccomp=unconfined <image>
#   /dev/kfd: "The main compute interface, shared by all GPUs."
#   /dev/dri: "Contains the Direct Rendering Interface (DRI) device nodes for each GPU."
ROCM_DEVICES="--device /dev/kfd --device /dev/dri --security-opt seccomp=unconfined"

remote() { ssh -o BatchMode=yes "$HOST" "$@"; }
have_image() { if remote "docker image inspect $1 >/dev/null 2>&1"; then echo yes; else echo no; fi; }

# Remember what was already there so cleanup removes only what this script added.
had_probe=$(have_image "$PROBE_IMAGE")
had_rocm=$(have_image "$ROCM_IMAGE")

cleanup() {
  echo "--- cleanup on $HOST"
  if [ "$had_probe" = no ]; then remote "docker image rm -f $PROBE_IMAGE >/dev/null 2>&1 || true"; fi
  if [ "$had_rocm" = no ]; then remote "docker image rm -f $ROCM_IMAGE >/dev/null 2>&1 || true"; fi
  echo "probe image present: $(have_image "$PROBE_IMAGE") (before this run: $had_probe)"
  echo "rocm image present:  $(have_image "$ROCM_IMAGE") (before this run: $had_rocm)"
}
trap cleanup EXIT

echo "--- host $HOST"
remote 'echo "arch=$(uname -m) kernel=$(uname -r)"; ls -l /dev/kfd; echo "/dev/dri: $(ls /dev/dri | tr "\n" " ")"; cat /sys/module/amdgpu/version 2>/dev/null || echo "amdgpu module version: not exposed"'

echo "--- ship the amd64 probe image (docker save | docker load, no registry involved)"
docker save --platform linux/amd64 "$PROBE_IMAGE" | remote 'docker load'

echo "--- 1. probe without devices"
remote "docker run --rm $PROBE_IMAGE"

echo "--- 2. probe with the ROCm device nodes"
remote "docker run --rm $ROCM_DEVICES $PROBE_IMAGE"

echo "--- 3. ROCm userland: rocminfo and rocm-smi"
remote "docker run --rm $ROCM_DEVICES $ROCM_IMAGE sh -c 'rocminfo | grep -E \"Name:|gfx\" | head -20; rocm-smi'"
