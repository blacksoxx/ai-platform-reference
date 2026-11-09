# GPUJobPendingTooLong and QueueStarvation

**GPUJobPendingTooLong**, warning: a Pod assigned to a KAI queue has been Pending for 15
minutes. **QueueStarvation**, warning: a queue has had Pending Pods for 30 minutes while at
least one allocated GPU in the cluster reports zero utilisation.

## Impact

The team's work is waiting. Nothing is broken when the cluster is simply full; something is
wrong when GPUs are held idle while others wait.

## Check

GPU queues dashboard: GPUs in the cluster versus requested, Pending Pods per queue, allocated
GPUs with zero utilisation. Then:

```sh
kubectl get pods -A -l kai.scheduler/queue --field-selector=status.phase=Pending
kubectl -n <namespace> describe pod <pod> | sed -n '/Events:/,$p'
kubectl get queues.scheduling.run.ai -o custom-columns='NAME:.metadata.name,GPU_QUOTA:.spec.resources.gpu.quota,GPU_LIMIT:.spec.resources.gpu.limit'
kubectl -n kai-scheduler logs deploy/scheduler --tail=100 | grep -i <pod>
```

The Pod's events, written by KAI, say which it is:

- **Queue at its limit**: the team already holds `limit` GPUs. Expected; the job runs when one
  frees up. If this is permanent, the team's `limit` in `tenants/<team>/kustomization.yaml`
  is the knob, through a pull request.
- **No GPU free in the cluster, other teams within quota**: the cluster is full. Capacity, or
  lower per-team limits so that nobody can take everything.
- **Over quota while another team is under quota and idle**: starvation. The idle allocations
  are listed by GPUAllocatedButIdle ([gpu-allocated-but-idle.md](gpu-allocated-but-idle.md));
  ask the team holding them, or let the queue's `overQuotaWeight` and KAI's reclaim settle it.
- **Unsatisfiable request** (events mention nodes that do not match): the Pod asks for a vendor
  label, a taint toleration or a resource no node offers. Fix the manifest.

## Fix

Through Git for quotas and limits; through the team for idle allocations; through capacity when
the cluster is full for real.

## After

Pending Pods per queue back to zero on the dashboard.
