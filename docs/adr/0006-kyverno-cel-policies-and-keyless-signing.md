# ADR 0006: Kyverno CEL policies and keyless image signatures

**Status**: accepted, 2026-11-09

## Context

Tenant workloads must be refused, not merely reported, when they run privileged, lack the
label the platform keys on, pull from an unknown registry, or run a platform image that was
not built by this repository. Options for the engine: Kubernetes ValidatingAdmissionPolicy
(CEL, built in, no image verification), Kyverno (`kyverno.io/v1` ClusterPolicy or the newer
CEL-based `policies.kyverno.io` types), OPA Gatekeeper. Options for signatures: a cosign key
pair kept somewhere, or keyless signing with the CI workflow's OIDC identity.

## Decision

Kyverno 1.19 with the CEL-based policy types: `ValidatingPolicy` for the three validation
rules and `ImageValidatingPolicy` for signature verification. The Kyverno CLI warns that
`kyverno.io/v1` ClusterPolicy is deprecated; the new types are the ones upstream develops.
Policies are scoped with a namespace selector on `ai-platform.io/tenant=true`, so platform
namespaces managed from this repository are out of scope. Images are signed keyless in
`images.yml` (cosign, GitHub Actions OIDC, recorded in Rekor); the policy accepts only the
identity of that workflow on `main` and mutates admitted references to digests. The validate
policies are unit-tested with `kyverno test` in `make lint`.

## Consequences

- No signing key to store or rotate; the trust anchor is the repository and branch name in
  the OIDC subject. Forks and other branches cannot produce admissible platform images.
- The registry allow list names the vendors the platform serves (vLLM, llama.cpp) and vCluster
  (whose control plane runs inside tenant namespaces); tenants bringing other images change the
  policy through a pull request.
- Signature verification needs the registry and Rekor reachable from the Kyverno Pods; a
  private registry package needs credentials in Kyverno and on the nodes, which is why the
  package is public.
- `ValidatingAdmissionPolicy` alone would have covered the three validation rules with no
  engine to run; image verification tipped it to Kyverno.
