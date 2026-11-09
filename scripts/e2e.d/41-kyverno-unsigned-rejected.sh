#!/bin/sh
# Proof: in a tenant namespace, a platform image without a verifiable Sigstore signature is
# refused, and the image signed by this repository's images workflow is admitted.
set -eu
k() { kubectl --context "$KUBE_CONTEXT" "$@"; }
ns=e2e-tenant-signing
cleanup() { k delete namespace "$ns" --ignore-not-found --wait=false >/dev/null 2>&1 || true; }
trap cleanup EXIT

k create namespace "$ns" --dry-run=client -o yaml | k apply -f - >/dev/null
k label namespace "$ns" ai-platform.io/tenant=true --overwrite >/dev/null

if out=$(k apply -n "$ns" -f - 2>&1 <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: unsigned
  labels:
    app.kubernetes.io/name: unsigned
spec:
  containers:
    - name: c
      image: ghcr.io/blacksoxx/ai-platform-reference/gpu-probe:not-signed
EOF
); then
  echo "NOT refused: image without a verifiable signature"; echo "$out" | sed 's/^/      /'; exit 1
fi
echo "refused as expected: image without a verifiable signature"
echo "$out" | grep -iE 'signature|verif' | head -1 | cut -c1-160 | sed 's/^/      /'

k apply -n "$ns" -f - >/dev/null <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: signed
  labels:
    app.kubernetes.io/name: signed
spec:
  restartPolicy: Never
  containers:
    - name: c
      image: ghcr.io/blacksoxx/ai-platform-reference/gpu-probe:main
EOF
image=$(k -n "$ns" get pod signed -o jsonpath='{.spec.containers[0].image}')
echo "admitted: signed image, mutated to its digest: $image"
case "$image" in *@sha256:*) ;; *) echo "expected the image reference to be mutated to a digest"; exit 1 ;; esac
