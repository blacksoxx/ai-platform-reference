#!/bin/sh
# Proof: team-a's queue has a limit of 2 GPUs. Three one-GPU jobs are submitted at once; two run
# and the third waits in the queue until a GPU is released, then runs. All three complete.
set -eu
k() { kubectl --context "$KUBE_CONTEXT" "$@"; }
cleanup() { k -n team-a delete jobs -l app.kubernetes.io/name=queue-probe --ignore-not-found --wait=false >/dev/null 2>&1 || true; }
trap cleanup EXIT

k get queues.scheduling.run.ai team-a >/dev/null
for i in 1 2 3; do
k apply -f - >/dev/null <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: queue-probe-$i
  namespace: team-a
  labels:
    app.kubernetes.io/name: queue-probe
spec:
  backoffLimit: 0
  template:
    metadata:
      labels:
        app.kubernetes.io/name: queue-probe
        kai.scheduler/queue: team-a
    spec:
      schedulerName: kai-scheduler
      restartPolicy: Never
      securityContext:
        runAsNonRoot: true
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: c
          image: ghcr.io/blacksoxx/ai-platform-reference/gpu-probe:main
          command: ["sleep", "45"]
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              memory: 128Mi
              nvidia.com/gpu: 1
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: [ALL]
EOF
done

sleep 30
running=$(k -n team-a get pods -l app.kubernetes.io/name=queue-probe --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')
pending=$(k -n team-a get pods -l app.kubernetes.io/name=queue-probe --field-selector=status.phase=Pending --no-headers 2>/dev/null | wc -l | tr -d ' ')
echo "after 30s: $running running, $pending waiting for quota (queue team-a: limit 2 GPUs)"
[ "$pending" -ge 1 ] || { echo "expected at least one job to wait for quota"; k -n team-a get pods -l app.kubernetes.io/name=queue-probe; exit 1; }

k -n team-a wait --for=condition=complete job -l app.kubernetes.io/name=queue-probe --timeout=300s >/dev/null
echo "all three jobs completed once GPUs were released"
