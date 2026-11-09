# InferenceNoBackend

**Severity**: critical. **Fires when**: for 10 minutes, no target of the `inference`
ServiceMonitor has been up: every backend behind the Service is down or still loading.

## Impact

Completion requests through the Gateway fail (HTTP 503 from the Gateway, no healthy
endpoint). The availability SLO burns from the first minute.

## Check

```sh
kubectl -n inference get deploy,pods -o wide
kubectl -n inference describe pod -l app.kubernetes.io/name=inference | grep -A12 Events:
kubectl -n inference logs deploy/inference-cpu --tail=50        # ci
kubectl -n inference logs deploy/inference-nvidia --tail=50     # lab, vLLM
kubectl -n inference logs deploy/inference-amd --tail=50        # lab, llama.cpp
kubectl -n inference get endpointslices
```

Typical causes, in order of frequency:

1. **Model download**: a cold start pulls the weights from Hugging Face; the readiness probe
   is red until the model is loaded (several minutes for 0.5 B on CPU, up to thirty for 7 B on
   a slow link). The Pod shows `0/1 Running`; logs show the download. Wait, or pre-pull.
2. **GPU not available**: the Pod is Pending with `Insufficient nvidia.com/gpu` or
   `amd.com/gpu`: the device plugin is down or the queue limit is reached. See
   [gpu-node-not-ready.md](gpu-node-not-ready.md).
3. **Out of memory**: the container was killed (`OOMKilled`); the model does not fit the
   limit or the GPU. Lower `--max-model-len` (vLLM), the context size (llama.cpp), or use a
   smaller quantisation; change it in Git.
4. **Image pull**: a digest that no longer exists or a registry outage; `ErrImagePull` in the
   events.

## Fix

Fix the cause above through Git (sizes, model, image) and let Argo CD apply it. If the last
change to `platform/inference` is the cause, [roll it back](inference-rollback.md).

## After

"Backends up" on the Inference dashboard counts the targets again; proof 80 answers.
