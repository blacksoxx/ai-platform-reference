# syntax=docker/dockerfile:1
# gpu-probe: a small multi-platform image that prints what the container sees.
#
# Base: ubuntu:24.04, pinned to the digest of the multi-platform index so arm64
# and amd64 resolve to the same release. Ubuntu rather than Alpine because the
# NVIDIA Container Toolkit mounts the host's nvidia-smi into the container and
# that binary needs glibc, which Alpine (musl) does not provide.
# Digest read on 2026-11-09 with: docker buildx imagetools inspect ubuntu:24.04
FROM ubuntu:24.04@sha256:fe81560990fae86dc4743202b2cb4d3df98d0bcf949173cecef15ce1127ef852

LABEL org.opencontainers.image.title="gpu-probe" \
      org.opencontainers.image.description="Prints architecture and visible NVIDIA/AMD GPU devices"

COPY --chmod=0755 probe.sh /usr/local/bin/gpu-probe

# Run as the unprivileged "ubuntu" user (uid 1000) that the base image ships.
# A probe has no reason to be root, and later admission policies will insist.
USER ubuntu

ENTRYPOINT ["/usr/local/bin/gpu-probe"]
