# ADR 0009: Kubernetes 1.36 in every environment

**Status**: accepted, 2026-11-09

## Context

On 2026-11-09 upstream Kubernetes was at 1.37.2. kind 0.33.0 ships node images for 1.37.0,
1.36.4, 1.35.8 and 1.34.11; RKE2 publishes v1.37.2+rke2r1 and v1.36.6+rke2r1; the operator's
kubectl is 1.36.2. Operators and charts in the stack publish their support matrices one minor
behind upstream.

## Decision

One minor everywhere: kind `1.36.4` (by digest) in ci, RKE2 `v1.36.6+rke2r1` in the lab,
kubectl 1.36.x on the operator's machine, kubeconform validation against 1.36.0 schemas.

## Consequences

- One minor to reason about in support matrices, one set of API versions in manifests, one
  schema set in lint.
- Upgrading is a coordinated change of four pins (kind image, RKE2 version, kubectl, lint
  schema version), done when the component matrices have caught up with the next minor.
