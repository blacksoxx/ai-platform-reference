#!/bin/sh
# Proof: an alert fired on purpose travels from a PrometheusRule through Prometheus to
# Alertmanager. The rule is created for the test and removed afterwards.
set -eu
k() { kubectl --context "$KUBE_CONTEXT" "$@"; }
pf=""
cleanup() {
  k -n monitoring delete prometheusrule e2e-test-alert --ignore-not-found >/dev/null 2>&1 || true
  [ -n "$pf" ] && kill "$pf" 2>/dev/null || true
}
trap cleanup EXIT

k apply -f - >/dev/null <<'EOF'
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: e2e-test-alert
  namespace: monitoring
spec:
  groups:
    - name: e2e
      rules:
        - alert: E2ETestAlert
          expr: vector(1)
          labels:
            severity: info
          annotations:
            summary: Fired on purpose by scripts/e2e.d/30-alert-pipeline.sh
EOF

k -n monitoring port-forward svc/monitoring-alertmanager 19093:9093 >/dev/null 2>&1 &
pf=$!
sleep 3

for i in $(seq 1 60); do
  if curl -s 'http://127.0.0.1:19093/api/v2/alerts?filter=alertname%3D%22E2ETestAlert%22' | grep -q '"alertname":"E2ETestAlert"'; then
    echo "E2ETestAlert active in Alertmanager after $((i * 5))s"
    exit 0
  fi
  sleep 5
done
echo "E2ETestAlert never reached Alertmanager within 300s"
exit 1
