#!/bin/sh
# Proof: a chat completion request sent through the platform Gateway is answered by the
# inference Service. The Gateway's LoadBalancer Service is reached with a port-forward and the
# route's hostname in the Host header, so the check does not depend on the host's routing to
# the LoadBalancer address.
set -eu
k() { kubectl --context "$KUBE_CONTEXT" "$@"; }

k -n inference rollout status deployment/inference-cpu --timeout=900s >/dev/null
svc=$(k -n platform-gateway get svc -o name | grep -E 'cilium-gateway-platform' | head -1)
[ -n "$svc" ] || { echo "no LoadBalancer Service for the Gateway in platform-gateway"; exit 1; }
k -n platform-gateway port-forward "$svc" 18080:80 >/dev/null 2>&1 &
pf=$!
trap 'kill $pf 2>/dev/null || true' EXIT
sleep 3

body='{"model":"ai-platform","messages":[{"role":"user","content":"Reply with the single word: ready"}],"max_tokens":8,"temperature":0}'
reply=$(curl -s --max-time 120 -H 'Host: inference.172-18-255-10.nip.io' -H 'Content-Type: application/json' \
  -d "$body" http://127.0.0.1:18080/v1/chat/completions)
content=$(printf '%s' "$reply" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["choices"][0]["message"]["content"].strip())' 2>/dev/null || true)
if [ -z "$content" ]; then
  echo "no completion in the response:"; printf '%s\n' "$reply" | cut -c1-300 | sed 's/^/      /'; exit 1
fi
echo "completion answered through the Gateway: \"$content\""
