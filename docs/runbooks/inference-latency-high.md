# InferenceLatencyHigh

**Severity**: warning. **Fires when**: the 95th percentile of vLLM's end-to-end request
latency has been above 10 seconds for 10 minutes.

## Impact

Clients wait; the latency SLO (p95 time to first token under 2 s) is at risk. Nothing is
down yet.

## Check

Inference dashboard: request latency p50/p95, requests queued, tokens per second, KV cache
usage. Then:

- **Queued requests rising, KV cache near 100 %**: saturation. More load than one GPU serves;
  see [inference-requests-queued.md](inference-requests-queued.md).
- **Latency up, queue flat, tokens per second down**: the GPU slowed down. Throttling
  ([gpu-temperature-high.md](gpu-temperature-high.md)) or another Pod sharing the GPU.
- **Latency up only for long prompts**: prompt length; `vllm:request_prompt_tokens` shows the
  distribution. A larger `--max-model-len` costs memory and time.
- **Latency up after a change**: the last commit to `platform/inference` (model, context,
  image). Roll it back ([inference-rollback.md](inference-rollback.md)).

```sh
kubectl -n inference logs deploy/inference-nvidia --tail=100 | grep -iE 'throughput|running|pending|cache'
```

## Fix

Capacity (a second replica on a second GPU, or the AMD backend taking more of the traffic
through route weights), limits (`max_tokens` per request at the client), or a rollback.

## After

p95 back under the objective on the dashboard; record the cause and the prompt sizes.
