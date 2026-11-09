#!/bin/sh
# The demo (docs/demo.md): the proofs in the order they are shown, with headings, against a
# running environment. Nothing waits for Applications here; run `make e2e` first.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
export KUBE_CONTEXT=${KUBE_CONTEXT:-kind-${KIND_CLUSTER:-ai-platform-ci}}
k() { kubectl --context "$KUBE_CONTEXT" "$@"; }

step() { printf '\n\033[1m== %s\033[0m\n' "$1"; }

step "1. The platform applies itself"
k get applications.argoproj.io -n argocd

step "2. GPUs are a scheduled resource"
k get nodes -o custom-columns='NAME:.metadata.name,GPU:.status.capacity.nvidia\.com/gpu'
sh "$HERE/e2e.d/10-gpu-job.sh"

step "3. Metrics, dashboards, an alert fired on purpose"
sh "$HERE/e2e.d/20-gpu-metrics.sh"
sh "$HERE/e2e.d/30-alert-pipeline.sh"

step "4. Admission refuses"
sh "$HERE/e2e.d/40-kyverno-privileged-rejected.sh"
sh "$HERE/e2e.d/41-kyverno-unsigned-rejected.sh"

step "5. Runtime detection"
sh "$HERE/e2e.d/50-falco-shell-alert.sh"

step "6. Two tenants, two queues, four GPUs"
sh "$HERE/e2e.d/70-tenant-rbac.sh"
sh "$HERE/e2e.d/71-tenant-network.sh"
sh "$HERE/e2e.d/72-kai-queue.sh"

step "7. A tenant's own cluster"
sh "$HERE/e2e.d/73-vcluster.sh"

step "8. A completion"
sh "$HERE/e2e.d/80-inference.sh"
