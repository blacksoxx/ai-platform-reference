#!/bin/sh
# Proof: a chat completion request sent through the platform Gateway is answered by the
# inference Service. The Gateway's LoadBalancer Service has no Pod selector (Cilium programs it
# in eBPF), so kubectl port-forward cannot reach it; the request is sent from inside the
# cluster instead, from the backend Pod (its image ships curl), to the Gateway's cluster address
# with the route's hostname in the Host header. It crosses the Gateway, the HTTPRoute and the
# Service the way an external client's request does.
set -eu
k() { kubectl --context "$KUBE_CONTEXT" "$@"; }

k -n inference rollout status deployment/inference-cpu --timeout=900s >/dev/null
k -n platform-gateway get svc cilium-gateway-platform >/dev/null

body='{"model":"ai-platform","messages":[{"role":"user","content":"Reply with the single word: ready"}],"max_tokens":8,"temperature":0}'
reply=$(k -n inference exec deploy/inference-cpu -- curl -s --max-time 120 \
  -H 'Host: inference.172-18-255-10.nip.io' -H 'Content-Type: application/json' \
  -d "$body" http://cilium-gateway-platform.platform-gateway.svc/v1/chat/completions)
content=$(printf '%s' "$reply" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["choices"][0]["message"]["content"].strip())' 2>/dev/null || true)
if [ -z "$content" ]; then
  echo "no completion in the response:"; printf '%s\n' "$reply" | cut -c1-300 | sed 's/^/      /'; exit 1
fi
echo "completion answered through the Gateway: \"$content\""
