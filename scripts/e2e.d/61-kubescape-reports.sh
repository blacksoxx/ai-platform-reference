#!/bin/sh
# Proof: Kubescape has run its configuration (posture) scan and stored per-workload results in
# the cluster.
set -eu
k() { kubectl --context "$KUBE_CONTEXT" "$@"; }

for i in $(seq 1 60); do
  scans=$(k get workloadconfigurationscans.spdx.softwarecomposition.kubescape.io -A --no-headers 2>/dev/null | wc -l | tr -d ' ')
  if [ "$scans" -gt 0 ]; then
    echo "WorkloadConfigurationScans: $scans"
    k get workloadconfigurationscansummaries.spdx.softwarecomposition.kubescape.io -A --no-headers 2>/dev/null | head -3 | sed 's/^/      /'
    exit 0
  fi
  sleep 10
done
echo "no Kubescape configuration scans after 600s"
exit 1
