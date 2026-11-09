# GPUAllocatedButIdle

**Severity**: info. **Fires when**: a GPU with a Pod attached (`pod` label set) has reported
0 % utilisation for 30 minutes.

## Impact

Nothing is broken. Quota is spent for nothing: the team's queue counts the GPU as used, so a
job of another team that would run on it waits (InferenceRequestsQueued or a Pending Pod).
The usual causes are a notebook left open, a job waiting on data, or a process that crashed
inside a container that is still running.

## Check

```sh
# which pod holds it
# after: kubectl -n monitoring port-forward svc/monitoring-prometheus 19090:9090
curl -s 'http://127.0.0.1:19090/api/v1/query?query=DCGM_FI_DEV_GPU_UTIL{pod!=""}==0'
kubectl -n <namespace> describe pod <pod> | sed -n '/Containers:/,/Conditions:/p'
kubectl -n <namespace> logs <pod> --tail=50
```

## Fix

- A tenant's interactive session: tell the team; the platform does not kill tenant Pods on
  idleness. If the team agrees, scale the Deployment to zero in their repository.
- A platform workload (`workloads/interactive-session` is one by design, as a demo of this
  alert): scale it in Git.
- A policy change, if this repeats: a lower queue `limit` for the team, or a time-based
  cleanup the team runs themselves.

## After

The alert resolves as soon as utilisation rises or the Pod is gone.
