# Rolling back an inference change

A change to `platform/inference` (model, image digest, context size, resources, a route) is
a commit; rolling it back is the reverse commit. Argo CD applies the revert like any other
change, and the Deployments use `strategy: Recreate` with one replica, so a rollback costs one
model load per backend.

## When

- InferenceNoBackend or InferenceBackendDown right after a change landed.
- InferenceLatencyHigh with no change in load after a change landed.
- Answers of a different quality after a model change the team did not expect.

## How

```sh
git log --oneline -- platform/inference | head -5          # find the change
git revert <commit>                                         # one revert commit, no history rewrite
git push origin main
```

Argo CD picks the revert up within two minutes (`timeout.reconciliation: 120s` in ci) and
replaces the Deployment. Watch it:

```sh
kubectl -n argocd get application inference
kubectl -n inference rollout status deployment/inference-cpu      # ci
kubectl -n inference rollout status deployment/inference-nvidia   # lab
```

To stop the bleeding before the revert lands, scale the bad backend to zero; the Service keeps
sending to the others. Argo CD will undo the scale when it syncs, which is fine once the
revert is in:

```sh
kubectl -n inference scale deployment/inference-nvidia --replicas=0
```

## Verify

```sh
KUBE_CONTEXT=<context> sh scripts/e2e.d/80-inference.sh
```

and the Inference dashboard: backends up, latency back on the objective.

## Do not

Do not `kubectl edit` the Deployment to fix it in place: Argo CD's self-heal reverts manual
edits, and the next sync would bring the bad change back. The fix goes through Git.
