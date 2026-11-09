#!/bin/sh
# End-to-end check of a running environment: every Argo CD Application Synced and Healthy, then
# the proofs in scripts/e2e.d/, one file per claim the platform makes (a privileged pod is
# refused, a GPU job is scheduled, a completion request is answered, ...).
#
# Usage: scripts/e2e.sh                 (or: make e2e)
# Env:   KUBE_CONTEXT (default kind-ai-platform-ci), E2E_TIMEOUT seconds (default 1200)
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
export KUBE_CONTEXT=${KUBE_CONTEXT:-kind-${KIND_CLUSTER:-ai-platform-ci}}
TIMEOUT=${E2E_TIMEOUT:-1200}
k() { kubectl --context "$KUBE_CONTEXT" "$@"; }

echo "== waiting up to ${TIMEOUT}s for every Application to be Synced and Healthy"
deadline=$(( $(date +%s) + TIMEOUT ))
while :; do
  apps=$(k get applications.argoproj.io -n argocd \
    -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.sync.status}{" "}{.status.health.status}{"\n"}{end}')
  total=$(printf '%s\n' "$apps" | grep -c . || true)
  pending=$(printf '%s\n' "$apps" | grep -vE ' Synced Healthy$' || true)
  if [ "$total" -gt 0 ] && [ -z "$pending" ]; then
    echo "all $total applications Synced and Healthy"
    break
  fi
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "TIMEOUT, still pending:"; printf '%s\n' "$pending"
    k get applications.argoproj.io -n argocd
    exit 1
  fi
  sleep 10
done
k get applications.argoproj.io -n argocd

echo "== proofs"
failed=0
for proof in "$HERE"/e2e.d/*.sh; do
  [ -f "$proof" ] || continue
  name=$(basename "$proof" .sh)
  if sh "$proof"; then echo "ok    $name"; else echo "FAIL  $name"; failed=1; fi
done
exit $failed
