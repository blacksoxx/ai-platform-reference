#!/bin/sh
# Proof: a Job requesting nvidia.com/gpu is scheduled on a node that advertises GPUs and runs
# to completion. Prints what the probe saw.
set -eu
k() { kubectl --context "$KUBE_CONTEXT" "$@"; }

k -n workloads wait --for=condition=complete job/gpu-probe --timeout=300s >/dev/null
pod=$(k -n workloads get pods -l job-name=gpu-probe -o jsonpath='{.items[0].metadata.name}')
node=$(k -n workloads get pod "$pod" -o jsonpath='{.spec.nodeName}')
capacity=$(k get node "$node" -o jsonpath='{.status.capacity.nvidia\.com/gpu}')
echo "gpu-probe completed on $node (nvidia.com/gpu capacity: ${capacity:-none})"
k -n workloads logs "$pod" | sed 's/^/      /'
[ -n "$capacity" ] && [ "$capacity" != "0" ]
