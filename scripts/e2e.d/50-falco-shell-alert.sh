#!/bin/sh
# Proof: an interactive shell opened in a running container is detected by Falco (rule
# "Terminal shell in container", priority NOTICE) and the event reaches Alertmanager through
# Falcosidekick. The shell is opened with a pseudo-terminal from python3, because the rule only
# fires for a shell with a terminal attached.
set -eu
k() { kubectl --context "$KUBE_CONTEXT" "$@"; }

k -n falco rollout status daemonset/falco --timeout=300s >/dev/null
k -n falco wait --for=condition=Ready pod -l app.kubernetes.io/name=falcosidekick --timeout=120s >/dev/null
target=$(k -n kube-system get pods -l k8s-app=cilium -o jsonpath='{.items[0].metadata.name}')

python3 - "$KUBE_CONTEXT" "$target" <<'EOF'
import pty, sys
ctx, pod = sys.argv[1], sys.argv[2]
pty.spawn(["kubectl", "--context", ctx, "-n", "kube-system", "exec", "-it", pod, "-c", "cilium-agent", "--", "sh", "-c", "echo e2e-shell-probe; exit"])
EOF

for i in $(seq 1 24); do
  if k -n falco logs daemonset/falco --since=5m 2>/dev/null | grep -q 'Terminal shell in container'; then
    echo "Falco detected the shell in $target (rule: Terminal shell in container)"
    break
  fi
  [ "$i" -eq 24 ] && { echo "Falco did not report the shell within 120s"; exit 1; }
  sleep 5
done

k -n monitoring port-forward svc/monitoring-alertmanager 19094:9093 >/dev/null 2>&1 &
pf=$!
trap 'kill $pf 2>/dev/null || true' EXIT
sleep 3
for i in $(seq 1 12); do
  if curl -s 'http://127.0.0.1:19094/api/v2/alerts' | grep -qi 'terminal.shell'; then
    echo "the event reached Alertmanager through Falcosidekick"
    exit 0
  fi
  sleep 5
done
echo "the Falco event never reached Alertmanager"
exit 1
