# InferenceBackendDown

**Severity**: warning. **Fires when**: one backend Pod of the inference Service has not
answered its metrics endpoint for 5 minutes while others still do.

## Impact

Capacity is reduced; requests go to the remaining backends. In the lab, that means one
vendor is out: if it is the NVIDIA side, every request is answered by llama.cpp on the AMD
box, at a different latency and quantisation.

## Check

```sh
kubectl -n inference get pods -o wide
kubectl -n inference logs <pod> --tail=100
kubectl -n inference describe pod <pod> | grep -A12 Events:
```

Same causes as [inference-no-backend.md](inference-no-backend.md), restricted to one backend:
a restart that is reloading the model, a GPU fault on that node
([gpu-xid-error.md](gpu-xid-error.md)), a node that went NotReady
([gpu-node-not-ready.md](gpu-node-not-ready.md)), an out-of-memory kill.

## Fix

Let a restart finish; otherwise fix the node or the Deployment through Git. Both Deployments
use `strategy: Recreate` with one replica, so a change rolls the backend with a gap of one
model load; plan it outside the busy hours.

## After

The Inference dashboard shows the backend's tokens per second again.
