#!/bin/sh
# Proof: in a tenant namespace, a privileged Pod, a Pod without the required label and a Pod
# from a foreign registry are refused at admission by Kyverno.
set -eu
k() { kubectl --context "$KUBE_CONTEXT" "$@"; }
ns=e2e-tenant
cleanup() { k delete namespace "$ns" --ignore-not-found --wait=false >/dev/null 2>&1 || true; }
trap cleanup EXIT

k create namespace "$ns" --dry-run=client -o yaml | k apply -f - >/dev/null
k label namespace "$ns" ai-platform.io/tenant=true --overwrite >/dev/null
# The policies are Kyverno ValidatingPolicy objects (policies/); each reports readiness in
# status.conditionStatus.ready once the admission controller serves it.
k wait --for=jsonpath='{.status.conditionStatus.ready}'=true validatingpolicies.policies.kyverno.io --all --timeout=120s >/dev/null

expect_denied() { # <description> <manifest on stdin>
  if out=$(k apply -n "$ns" -f - 2>&1); then
    echo "NOT refused: $1"; echo "$out" | sed 's/^/      /'; return 1
  fi
  echo "refused as expected: $1"; echo "$out" | grep -E 'policy|message' | head -2 | sed 's/^/      /'
}

expect_denied "privileged container" <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: privileged
  labels:
    app.kubernetes.io/name: privileged
spec:
  containers:
    - name: c
      image: ghcr.io/blacksoxx/ai-platform-reference/gpu-probe:main
      securityContext:
        privileged: true
EOF

expect_denied "missing app.kubernetes.io/name label" <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: unlabelled
spec:
  containers:
    - name: c
      image: ghcr.io/blacksoxx/ai-platform-reference/gpu-probe:main
EOF

expect_denied "image from a foreign registry" <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: foreign
  labels:
    app.kubernetes.io/name: foreign
spec:
  containers:
    - name: c
      image: docker.io/library/nginx:1.27
EOF
