#!/bin/sh
# Proof: an interactive shell opened in a running container is detected by Falco (rule
# "Terminal shell in container", priority NOTICE) and the event reaches Alertmanager through
# Falcosidekick. The shell is opened with a pseudo-terminal from python3, because the rule only
# fires for a shell with a terminal attached.
set -eu
k() { kubectl --context "$KUBE_CONTEXT" "$@"; }

k -n falco rollout status daemonset/falco --timeout=300s >/dev/null
k -n falco wait --for=condition=Ready pod -l app.kubernetes.io/name=falcosidekick --timeout=120s >/dev/null
# Falco sees the node it runs on: pick one Falco Pod, open the shell in a container on that
# node (the Cilium agent there, always present), and read that Falco Pod's own logs.
falco_pod=$(k -n falco get pods -l app.kubernetes.io/name=falco --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')
node=$(k -n falco get pod "$falco_pod" -o jsonpath='{.spec.nodeName}')
target=$(k -n kube-system get pods -l k8s-app=cilium --field-selector="spec.nodeName=$node" -o jsonpath='{.items[0].metadata.name}')
[ -n "$falco_pod" ] && [ -n "$target" ] || { echo "no Falco Pod or no Cilium agent on node '$node'"; exit 1; }

python3 - "$KUBE_CONTEXT" "$target" <<'EOF'
import pty, sys
ctx, pod = sys.argv[1], sys.argv[2]
pty.spawn(["kubectl", "--context", ctx, "-n", "kube-system", "exec", "-it", pod, "-c", "cilium-agent", "--", "sh", "-c", "echo e2e-shell-probe; exit"])
EOF

for i in $(seq 1 24); do
  if line=$(k -n falco logs "$falco_pod" --since=5m 2>/dev/null | grep 'Terminal shell in container' | tail -1) && [ -n "$line" ]; then
    echo "Falco on $node detected the shell in $target (rule: Terminal shell in container)"
    printf '%s\n' "$line" | cut -c1-200 | sed 's/^/      /'
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
