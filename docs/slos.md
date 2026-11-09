# Service level objectives

Objectives for what the platform promises its tenants, the indicators that measure them, and
the alerts that fire before an objective is at risk. Windows are 30 days rolling. Numbers are
the targets for the lab; ci checks the indicators exist and move.

## Inference endpoint

The OpenAI-compatible endpoint at `inference.<env>/v1/chat/completions`.

| Objective | Target | Indicator (Prometheus) | Guarding alert |
|---|---|---|---|
| Availability: a completion request is answered with HTTP 2xx | 99.5 % of requests, 30 days | `sum(rate(vllm:request_success_total[5m]))` over `sum(rate(vllm:request_success_total[5m])) + failed requests seen at the Gateway` (Envoy `envoy_cluster_upstream_rq` by response class, from Hubble/Envoy metrics) | InferenceNoBackend, InferenceBackendDown |
| Latency: time to first token | p95 under 2 s for prompts under 1 k tokens | `histogram_quantile(0.95, sum by (le) (rate(vllm:time_to_first_token_seconds_bucket[5m])))` | InferenceLatencyHigh (end to end p95 over 10 s) |
| Throughput floor per backend | at least 20 generated tokens/s per GPU backend under load | `sum by (app_kubernetes_io_component) (rate(vllm:generation_tokens_total[5m]) or rate(llamacpp:tokens_predicted_total[5m]))` | InferenceRequestsQueued |

Error budget: 0.5 % of requests over 30 days. Spending it on a planned rollout is fine; the
[rollback runbook](runbooks/inference-rollback.md) is the way back when the budget burns.

## GPU scheduling for tenants

| Objective | Target | Indicator | Guarding alert |
|---|---|---|---|
| Queue wait: a job within its queue's guaranteed quota starts | within 5 minutes, 99 % of the time | time between Pod creation and `PodScheduled=True` for Pods labelled `kai.scheduler/queue`, from kube-state-metrics (`kube_pod_status_scheduled_time - kube_pod_created`) | GPUJobPendingTooLong (15 minutes Pending), QueueStarvation (waiting while allocated GPUs idle) |
| GPU availability: every GPU node is Ready | 99 % of the time | `kube_node_status_condition{condition="Ready",status="true"}` on nodes with GPU capacity | GPUNodeNotReady |
| GPU health: no unresolved XID error | zero for longer than 15 minutes | `DCGM_FI_DEV_XID_ERRORS` | GPUXidError |

## Platform control plane

| Objective | Target | Indicator | Guarding alert |
|---|---|---|---|
| Admission: the policy webhook answers | 99.9 % of admission requests within the webhook timeout | Kyverno admission controller metrics (`kyverno_admission_requests_total`, `kyverno_admission_review_duration_seconds`) | default rules of kube-prometheus-stack for the Deployment |
| GitOps: a merged change is applied | within 5 minutes of the merge, 99 % of changes | Argo CD `argocd_app_sync_total` and `argocd_app_info` sync status | Argo CD's own OutOfSync status |
| Observability: metrics are being collected | Prometheus up and scraping every ServiceMonitor target | `up` per job | kube-prometheus-stack default rules (TargetDown) |

## How to read a breach

1. The alert's `runbook_url` opens the page for it under [runbooks/](runbooks/).
2. Grafana's Inference and GPU folders show the indicator over the window.
3. If the cause is a change, revert it in Git; Argo CD applies the revert like any other
   commit. If the cause is hardware, the GPU node runbooks say what to check on the node.
