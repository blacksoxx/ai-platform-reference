# Architecture decision records

One record per decision that shaped the platform: the context, the options that were on the
table, what was chosen and what it costs. Records are numbered in the order they were taken
and are never edited after the fact; a reversal is a new record that supersedes the old one.

| ADR | Decision |
|---|---|
| [0001](0001-kustomize-helm-charts-under-argocd.md) | Kustomize overlays with upstream Helm charts, rendered by Argo CD |
| [0002](0002-vault-and-external-secrets.md) | Vault in-cluster behind External Secrets Operator |
| [0003](0003-cilium-kube-proxy-free-gateway-api.md) | Cilium without kube-proxy, Gateway API as the only entry point |
| [0004](0004-kai-scheduler.md) | KAI Scheduler queues for GPU sharing |
| [0005](0005-vcluster-per-tenant.md) | A vCluster per tenant inside the tenant namespace |
| [0006](0006-kyverno-cel-policies-and-keyless-signing.md) | Kyverno CEL policies and keyless image signatures |
| [0007](0007-fake-gpu-operator-in-ci.md) | Simulated GPUs in ci with the Run:ai fake GPU operator |
| [0008](0008-gpu-operator-and-amd-device-plugin.md) | NVIDIA GPU Operator without driver and toolkit; AMD device plugin, not the AMD operator |
| [0009](0009-kubernetes-1-36.md) | Kubernetes 1.36 in every environment |
| [0010](0010-inference-backends.md) | vLLM on NVIDIA, llama.cpp on AMD and CPU, one Service |

Template: **Status**, **Context**, **Decision**, **Consequences**.
