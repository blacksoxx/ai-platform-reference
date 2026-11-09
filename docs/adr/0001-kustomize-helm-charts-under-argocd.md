# ADR 0001: Kustomize overlays with upstream Helm charts, rendered by Argo CD

**Status**: accepted, 2026-11-09

## Context

Most components are upstream Helm charts; the rest are plain manifests (policies, tenants,
workloads, dashboards, alerts). Two environments (ci, lab) differ in sizes, placement,
hostnames and the GPU layer. Argo CD must render everything, and `make lint` must render it
the same way so that CI catches what Argo CD would reject.

Options considered: Argo CD multi-source Applications (chart from a repository, values from
Git); Helm umbrella charts per environment; Kustomize everywhere with the `helmCharts` field.

## Decision

Every component is a Kustomize directory with `base/` and `overlays/{ci,lab}`. Upstream
charts are declared in each overlay's `kustomization.yaml` under `helmCharts`, pinned to a
version, with `valuesFile: ../../base/values.yaml` and an environment `values.yaml` in
`additionalValuesFiles`. Argo CD is configured with
`kustomize.buildOptions: --enable-helm --load-restrictor LoadRestrictionsNone`, and
`scripts/lint.sh` renders every overlay with the same flags and validates it with kubeconform.

The chart version is repeated in the two overlays of a component; lint fails if they differ.

## Consequences

- One rendering path, one validation path, one mental model: `kustomize build` of a directory
  is what runs in the cluster. Plain manifests and charts live side by side.
- `LoadRestrictionsNone` is required because overlays reference the base values file; the
  repository is the trust boundary, so the restriction buys nothing here.
- Helm hooks in charts become Argo CD hooks; charts that rely on hook Jobs for certificates
  are reconfigured to use cert-manager instead (kube-prometheus-stack's admission webhook).
- The repo-server needs network access to chart repositories at render time; renders are
  cached by Argo CD.
