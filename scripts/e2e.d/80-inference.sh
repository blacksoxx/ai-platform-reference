#!/bin/sh
# Proof: a chat completion request sent to the platform Gateway over TLS is answered by the
# inference Service. The request comes from a short-lived client Pod, the way a real client's
# does: it connects to the Gateway with the route's hostname (TLS SNI and Host), verifies the
# certificate against the platform root CA that cert-manager issued, and crosses the Gateway,
# the HTTPRoute and the Service before it reaches a backend. The Gateway's LoadBalancer address
# is not needed, and it is not reachable from every machine that runs kind (docs/setup-ci.md),
# so the client resolves the hostname to the Gateway Service's cluster address instead.
set -eu
k() { kubectl --context "$KUBE_CONTEXT" "$@"; }

ns=inference
client=e2e-inference-client
cleanup() { k -n "$ns" delete "pod/$client" "configmap/$client" --ignore-not-found --wait=false >/dev/null 2>&1 || true; }
trap cleanup EXIT INT TERM

k -n "$ns" rollout status deployment/inference-cpu --timeout=900s >/dev/null
host=$(k -n "$ns" get httproute inference -o jsonpath='{.spec.hostnames[0]}')
gateway_ip=$(k -n platform-gateway get svc cilium-gateway-platform -o jsonpath='{.spec.clusterIP}')
ca=$(k -n cert-manager get secret platform-root-ca -o jsonpath='{.data.ca\.crt}' | base64 -d)
if [ -z "$host" ] || [ -z "$gateway_ip" ] || [ -z "$ca" ]; then
  echo "missing one of: route hostname ($host), Gateway cluster address ($gateway_ip), platform root CA"; exit 1
fi

cleanup
k -n "$ns" create configmap "$client" --from-literal=ca.crt="$ca" >/dev/null
# The namespace enforces the restricted Pod Security Standard; the client meets it.
k -n "$ns" apply -f - >/dev/null <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: $client
  labels:
    app.kubernetes.io/name: e2e-inference-client
    app.kubernetes.io/part-of: ai-platform
spec:
  restartPolicy: Never
  securityContext:
    runAsNonRoot: true
    runAsUser: 100 # curl_user in the image, by number
    runAsGroup: 101
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: curl
      # docker.io/curlimages/curl:8.23.0, multi-arch index pinned by digest on 2026-11-10.
      image: docker.io/curlimages/curl:8.23.0@sha256:3fb7e13e5d179a845c97d78204f3f1064d1907037f26a3ebf91710571151fd93
      args:
        - -sS
        - --max-time
        - "120"
        - --cacert
        - /ca/ca.crt
        - --resolve
        - $host:443:$gateway_ip
        - -H
        - "Content-Type: application/json"
        - -d
        - '{"model":"ai-platform","messages":[{"role":"user","content":"Reply with the single word: ready"}],"max_tokens":8,"temperature":0}'
        - https://$host/v1/chat/completions
      resources:
        requests:
          cpu: 10m
          memory: 32Mi
        limits:
          memory: 64Mi
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities:
          drop: [ALL]
      volumeMounts:
        - name: ca
          mountPath: /ca
          readOnly: true
  volumes:
    - name: ca
      configMap:
        name: $client
YAML

# curl gives up after 120 s; allow for image pull and scheduling on top.
phase=""
i=0
while [ "$i" -lt 48 ]; do
  phase=$(k -n "$ns" get pod "$client" -o jsonpath='{.status.phase}' 2>/dev/null || true)
  case "$phase" in Succeeded|Failed) break ;; esac
  i=$((i + 1)); sleep 5
done
reply=$(k -n "$ns" logs "$client" 2>/dev/null || true)
if [ "$phase" != "Succeeded" ]; then
  echo "client Pod ended in phase '${phase:-unknown}':"
  printf '%s\n' "$reply" | cut -c1-300 | sed 's/^/      /'
  k -n "$ns" get pod "$client" -o jsonpath='{range .status.containerStatuses[*]}{.state}{"\n"}{end}' 2>/dev/null | cut -c1-300 | sed 's/^/      /'
  exit 1
fi
content=$(printf '%s' "$reply" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["choices"][0]["message"]["content"].strip())' 2>/dev/null || true)
if [ -z "$content" ]; then
  echo "no completion in the response:"; printf '%s\n' "$reply" | cut -c1-300 | sed 's/^/      /'; exit 1
fi
echo "completion answered through the Gateway over TLS (https://$host): \"$content\""
