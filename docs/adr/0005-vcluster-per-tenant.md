# ADR 0005: A vCluster per tenant inside the tenant namespace

**Status**: accepted, 2026-11-09

## Context

Teams want their own Kubernetes API: their own namespaces, CRDs and RBAC, without seeing other
teams and without a cluster each. Options: namespaces with RBAC only; a cluster per team;
virtual clusters (vCluster) whose control plane runs as Pods on the shared cluster and whose
workloads are synced to it.

## Decision

Each tenant directory adds the `loft/vcluster` chart with the team's name as release name,
in the team's namespace. The control plane runs there as a StatefulSet; Pods created in the
virtual cluster are synced into the same host namespace, so the quota, LimitRange, network
policy and Kyverno policies of the tenant package apply to them. Hybrid scheduling is on with
`kai-scheduler` as a host scheduler, so synced Pods that name it are placed by KAI with the
team's queue label. vCluster's own quota, limit range and network policy stay off; the tenant
package owns them.

## Consequences

- One API per team with full RBAC freedom inside, one host cluster to operate, one set of
  guard rails enforced on the host where the team cannot change them.
- The control plane is a tenant-namespace workload: it runs as root (the namespace enforces
  the baseline profile, not restricted), its image registry is on the allow list, and its Pod
  carries the required label. The hosts-rewrite init container is disabled because its image
  comes from a registry the policy does not allow.
- The virtual cluster's kubeconfig is a Secret (`vc-<team>`) in the team namespace; reaching
  the API from outside goes through a port-forward or a route the team publishes.
- Persistence for the control plane is `auto`: a PersistentVolumeClaim when a StorageClass
  exists (kind has one), an emptyDir otherwise.
