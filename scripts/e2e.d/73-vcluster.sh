#!/bin/sh
# Proof: team-a's virtual cluster answers as a Kubernetes API of its own, and a Pod created
# inside it is synced to the host cluster into the team's namespace, where it runs.
set -eu
k() { kubectl --context "$KUBE_CONTEXT" "$@"; }
pf=""
cleanup() {
  [ -n "$pf" ] && kill "$pf" 2>/dev/null || true
  rm -f /tmp/vc-team-a.kubeconfig
}
trap cleanup EXIT

k -n team-a wait --for=condition=Ready pod -l app=vcluster --timeout=600s >/dev/null
for i in $(seq 1 30); do
  k -n team-a get secret vc-team-a >/dev/null 2>&1 && break
  sleep 5
done
k -n team-a get secret vc-team-a -o jsonpath='{.data.config}' | base64 -d >/tmp/vc-team-a.kubeconfig

k -n team-a port-forward svc/team-a 18443:443 >/dev/null 2>&1 &
pf=$!
sleep 3
vk() { kubectl --kubeconfig /tmp/vc-team-a.kubeconfig --server https://127.0.0.1:18443 --insecure-skip-tls-verify "$@"; }

echo "inside the virtual cluster: $(vk get namespaces --no-headers | wc -l | tr -d ' ') namespaces, nodes: $(vk get nodes --no-headers | awk '{print $1}' | tr '\n' ' ')"

vk apply -f - >/dev/null <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: hello-from-vcluster
  labels:
    app.kubernetes.io/name: hello-from-vcluster
spec:
  restartPolicy: Never
  securityContext:
    runAsNonRoot: true
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: c
      image: ghcr.io/blacksoxx/ai-platform-reference/gpu-probe:main
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop: [ALL]
EOF

for i in $(seq 1 60); do
  host_pod=$(k -n team-a get pods -o name 2>/dev/null | grep 'hello-from-vcluster' | head -1 || true)
  if [ -n "$host_pod" ]; then
    phase=$(k -n team-a get "$host_pod" -o jsonpath='{.status.phase}')
    case "$phase" in Succeeded|Running) echo "synced to the host as team-a/${host_pod#pod/} ($phase)"; vk delete pod hello-from-vcluster --wait=false >/dev/null 2>&1 || true; exit 0 ;; esac
  fi
  sleep 5
done
echo "the Pod created in the virtual cluster never ran on the host"
exit 1
