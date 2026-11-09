# ADR 0010: vLLM on NVIDIA, llama.cpp on AMD and CPU, one Service

**Status**: accepted, 2026-11-09

## Context

The platform exists to serve models. The NVIDIA node runs CUDA 13 on a GB10 (arm64); the
AMD node is a Ryzen AI Max+ APU for which AMD documents PyTorch support and no vLLM support,
while llama.cpp with HIP runs on it; ci has no GPU at all. Clients should not care which
backend answers. Options: one serving stack everywhere (impossible on the APU), llm-d (a
distributed vLLM, more than two nodes need), or per-vendor backends behind one front door.

## Decision

One Service, `inference`, selects every backend by `app.kubernetes.io/name: inference`; one
HTTPRoute exposes it. Backends: NVIDIA's vLLM container on the Spark (`vllm serve
--served-model-name ai-platform`), llama.cpp's ROCm server image on the Halo, and llama.cpp's
CPU server image in ci, all with the model alias `ai-platform`, port 8000 and the OpenAI API.
Models: Qwen2.5-7B-Instruct in the lab (safetensors for vLLM, GGUF q4_k_m for llama.cpp),
Qwen2.5-0.5B-Instruct GGUF in ci, pulled from Hugging Face at start into an emptyDir cache.
Both backends expose Prometheus metrics; the ServiceMonitor carries the component label so
dashboards and alerts can tell the vendors apart.

## Consequences

- Clients see one endpoint and one model name; the Service load-balances across vendors,
  which the inference dashboard makes visible. Weighted or header-based routing between
  backends is an HTTPRoute change away.
- Weights are downloaded at every cold start (15 GB for vLLM); a persistent cache is a
  storage decision for the lab (setup-lab.md).
- The two backends are not identical in quality or latency: the same 7B model at fp16 on vLLM
  and at q4_k_m on llama.cpp. The SLOs measure the endpoint, not a backend.
- The lab manifests are written against the image manifests and the vendors' documentation
  and are validated on the hardware, not in ci.
