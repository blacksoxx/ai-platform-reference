# ADR 0004: KAI Scheduler queues for GPU sharing

**Status**: accepted, 2026-11-09

## Context

Two teams share a handful of GPUs. The default scheduler offers no notion of a team's share:
whoever submits first takes the GPU, and quotas per namespace are static ceilings that leave
hardware idle. Options: namespace ResourceQuotas only; Kueue (queues and quotas, job-level);
KAI Scheduler (NVIDIA, formerly Run:ai, pod-level queues with fair share, over-quota weights,
gang scheduling); Volcano.

## Decision

KAI Scheduler (`platform/kai-scheduler`) is installed in both environments. Every tenant has
a leaf `Queue` under the chart's `default-parent-queue` with a guaranteed `quota`, a hard
`limit` and an `overQuotaWeight` for spare capacity. Workloads opt in per Pod with
`schedulerName: kai-scheduler` and the label `kai.scheduler/queue: <team>`; everything else
keeps the default scheduler. Namespace ResourceQuotas remain as the outer ceiling.

## Consequences

- Fair sharing with guarantees: a team always gets its quota and may borrow idle capacity up
  to its limit; a third job beyond the limit waits and runs when a GPU frees up (proof 72).
- Two schedulers in the cluster; the proof and the tenant workloads show the opt-in pattern.
  Pods created inside a tenant's vCluster do not reach KAI (hybrid scheduling is a vCluster
  enterprise feature, ADR 0005); queued work is deployed in the tenant namespace through the
  team's Argo CD project.
- Quota beats node labels: nobody has to know which node is theirs, and a GPU never idles
  because a label pinned it to the wrong team.
- Kueue would also have worked and is the Kubernetes SIG project; KAI was chosen for pod-level
  queues that match how inference and notebook workloads are actually submitted.
