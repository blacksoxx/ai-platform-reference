#!/bin/sh
# Proof: a Pod in team-a can reach team-a's vCluster API and cannot reach team-b's. The
# CiliumNetworkPolicy of the tenant package drops the cross-tenant connection. Both tests use
# bash's /dev/tcp from the signed platform image, so nothing new is pulled.
set -eu
k() { kubectl --context "$KUBE_CONTEXT" "$@"; }
cleanup() { k -n team-a delete pod netcheck --ignore-not-found --wait=false >/dev/null 2>&1 || true; }
trap cleanup EXIT

k -n team-a wait --for=condition=Ready pod -l app=vcluster --timeout=600s >/dev/null
k -n team-b wait --for=condition=Ready pod -l app=vcluster --timeout=600s >/dev/null

k apply -f - >/dev/null <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: netcheck
  namespace: team-a
  labels:
    app.kubernetes.io/name: netcheck
spec:
  restartPolicy: Never
  securityContext:
    runAsNonRoot: true
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: c
      image: ghcr.io/blacksoxx/ai-platform-reference/gpu-probe:main
      command: ["sleep", "300"]
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop: [ALL]
EOF
k -n team-a wait --for=condition=Ready pod/netcheck --timeout=300s >/dev/null

tcp() { k -n team-a exec netcheck -- bash -c "timeout 5 bash -c '</dev/tcp/$1/443' 2>/dev/null"; }

if tcp team-a.team-a.svc; then echo "team-a -> team-a vCluster API: reachable"; else echo "team-a cannot reach its own vCluster API"; exit 1; fi
if tcp team-b.team-b.svc; then echo "NOT isolated: team-a reached team-b's vCluster API"; exit 1; else echo "team-a -> team-b vCluster API: dropped by the network policy"; fi
