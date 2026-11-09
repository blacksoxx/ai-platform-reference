#!/bin/sh
# Proof: GPU metrics with dcgm-exporter names (the same in ci with simulated GPUs and in lab
# with real ones) are being scraped by the platform Prometheus.
set -eu
k() { kubectl --context "$KUBE_CONTEXT" "$@"; }

k -n monitoring port-forward svc/monitoring-prometheus 19090:9090 >/dev/null 2>&1 &
pf=$!
trap 'kill $pf 2>/dev/null || true' EXIT
sleep 3

for i in $(seq 1 30); do
  series=$(curl -s 'http://127.0.0.1:19090/api/v1/query?query=count(DCGM_FI_DEV_GPU_UTIL)' \
    | sed -n 's/.*"value":\[[^,]*,"\([0-9]*\)".*/\1/p')
  if [ -n "$series" ] && [ "$series" -gt 0 ]; then
    echo "DCGM_FI_DEV_GPU_UTIL: $series series in Prometheus"
    exit 0
  fi
  sleep 10
done
echo "no DCGM_FI_DEV_GPU_UTIL series in Prometheus after 300s"
exit 1
