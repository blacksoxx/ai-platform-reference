#!/bin/sh
# Proof: Kubescape runs its configuration (posture) scan and stores per-workload results in the
# cluster, served by its storage APIService. The scan is scheduled daily by the chart's
# kubescape-scheduler CronJob; the proof triggers one run of it so it does not wait for the
# schedule, and reads the results through the aggregated API.
set -eu
k() { kubectl --context "$KUBE_CONTEXT" "$@"; }
job=e2e-posture-scan
cleanup() { k -n kubescape delete job "$job" --ignore-not-found --wait=false >/dev/null 2>&1 || true; }
trap cleanup EXIT

k wait --for=condition=Available apiservice/v1beta1.spdx.softwarecomposition.kubescape.io --timeout=120s >/dev/null
existing=$(k get workloadconfigurationscans.spdx.softwarecomposition.kubescape.io -A --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "${existing:-0}" -eq 0 ]; then
  cleanup
  k -n kubescape create job "$job" --from=cronjob/kubescape-scheduler >/dev/null
  echo "posture scan triggered from the kubescape-scheduler CronJob"
fi

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
