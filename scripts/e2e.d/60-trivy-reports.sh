#!/bin/sh
# Proof: Trivy Operator has scanned workloads and written VulnerabilityReports and
# ConfigAuditReports into the cluster.
set -eu
k() { kubectl --context "$KUBE_CONTEXT" "$@"; }

for i in $(seq 1 60); do
  vulns=$(k get vulnerabilityreports.aquasecurity.github.io -A --no-headers 2>/dev/null | wc -l | tr -d ' ')
  audits=$(k get configauditreports.aquasecurity.github.io -A --no-headers 2>/dev/null | wc -l | tr -d ' ')
  if [ "$vulns" -gt 0 ] && [ "$audits" -gt 0 ]; then
    echo "VulnerabilityReports: $vulns, ConfigAuditReports: $audits"
    k get vulnerabilityreports.aquasecurity.github.io -A --no-headers 2>/dev/null | head -3 | sed 's/^/      /'
    exit 0
  fi
  sleep 10
done
echo "no Trivy reports after 600s (VulnerabilityReports: $vulns, ConfigAuditReports: $audits)"
exit 1
