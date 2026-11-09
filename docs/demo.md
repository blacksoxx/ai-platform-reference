# Demo

A ten-minute walk through a running environment, in the order a platform engineer would show
it to a team that is about to use it. Every step is a command; `make demo` runs the proof
scripts behind the steps in sequence with headings.

## 1. The platform applies itself

Argo CD, with every Application Synced and Healthy, wave by wave:

```sh
kubectl get applications -n argocd
```

Open Argo CD (https://argocd.172-18-255-10.nip.io) and show the `root` Application: the tree
is the repository.

## 2. GPUs are a scheduled resource

```sh
kubectl get nodes -o custom-columns='NAME:.metadata.name,GPU:.status.capacity.nvidia\.com/gpu'
kubectl -n workloads logs job/gpu-probe
```

The probe printed what the container saw. In ci it is a simulated Tesla T4; in the lab it is
the Spark's GB10 or the Halo's render node.

## 3. Metrics, dashboards, an alert fired on purpose

Grafana, GPU folder: the DCGM dashboard. Then:

```sh
sh scripts/e2e.d/30-alert-pipeline.sh
```

A rule is created, fires, reaches Alertmanager, and is removed.

## 4. Admission refuses

```sh
sh scripts/e2e.d/40-kyverno-privileged-rejected.sh
sh scripts/e2e.d/41-kyverno-unsigned-rejected.sh
```

A privileged Pod, an unlabelled Pod, a Pod from a foreign registry, and an unsigned platform
image are refused with the policy's message. The signed image is admitted and rewritten to
its digest.

## 5. Runtime detection

```sh
sh scripts/e2e.d/50-falco-shell-alert.sh
```

A terminal shell opened in a container is reported by Falco and shows up in Alertmanager next
to the Prometheus alerts.

## 6. Two tenants, two queues, four GPUs

```sh
sh scripts/e2e.d/70-tenant-rbac.sh
sh scripts/e2e.d/71-tenant-network.sh
sh scripts/e2e.d/72-kai-queue.sh
```

A team member is confined to the team namespace; traffic between tenants is dropped (open
Hubble to watch it); three one-GPU jobs are submitted against a two-GPU queue limit, two run,
one waits, all complete.

## 7. A tenant's own cluster

```sh
sh scripts/e2e.d/73-vcluster.sh
```

A Pod created in team-a's virtual cluster is scheduled by KAI on the host, in team-a's
namespace, under team-a's quota and network policy.

## 8. A completion

```sh
curl -k https://inference.172-18-255-10.nip.io/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"ai-platform","messages":[{"role":"user","content":"Which GPU vendor are you running on?"}],"max_tokens":64}'
```

The model does not know, which is the point: the client asked `ai-platform` and the Service
picked a backend. In the lab, the inference dashboard shows which vendor answered.

## 9. Change something

Edit a value, commit, push. Argo CD applies it within two minutes; `make ci-status` shows the
Application go OutOfSync, Progressing, Healthy. Revert the commit to roll it back.
