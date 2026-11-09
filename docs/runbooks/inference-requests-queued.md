# InferenceRequestsQueued

**Severity**: warning. **Fires when**: more than 10 requests have been waiting in front of
the backends (vLLM's waiting queue plus llama.cpp's deferred requests) for 10 minutes.

## Impact

Requests are accepted but wait; latency rises for everyone. The backends are saturated or one
of them is gone and the other carries the load.

## Check

Inference dashboard: requests queued per backend, backends up, tokens per second.

```sh
kubectl -n inference get pods -o wide
# after: kubectl -n monitoring port-forward svc/monitoring-prometheus 19090:9090
curl -s 'http://127.0.0.1:19090/api/v1/query?query=sum by (app_kubernetes_io_component) (vllm:num_requests_waiting or llamacpp:requests_deferred)'
```

- One backend down: [inference-backend-down.md](inference-backend-down.md).
- Both up, both queuing: load exceeds capacity.
- One backend queuing, the other idle: the Service spreads requests evenly regardless of
  speed; the slow backend queues. Route weights on the HTTPRoute can shift the split.

## Fix

Short term: client-side limits (`max_tokens`, concurrency). Medium term: a second replica on
another GPU, a smaller or quantised model for the slower backend, or an HTTPRoute weight that
sends the larger share to the faster vendor; all through Git.

## After

Queue depth back to zero at idle; the SLO's throughput floor met per backend.
