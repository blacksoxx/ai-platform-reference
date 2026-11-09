#!/bin/sh
# Bootstrap the ci environment: a kind cluster, the Gateway API CRDs, Cilium as the CNI, Argo CD,
# and the root Application. From then on Argo CD applies everything else from the repository.
#
# Usage: clusters/ci/bootstrap.sh            (or: make ci-up)
# Env:   GITHUB_TOKEN   optional; lets Argo CD read the repository while it is private
#        KIND_CLUSTER   cluster name (default: ai-platform-ci, must match kind-config.yaml)
# Needs: docker, kind, kubectl, helm, kustomize, cilium (CLI).
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
CLUSTER=${KIND_CLUSTER:-ai-platform-ci}
CONTEXT="kind-$CLUSTER"
CILIUM_VERSION=1.20.4          # https://raw.githubusercontent.com/cilium/cilium/main/stable.txt, 2026-11-09
GATEWAY_API_VERSION=v1.6.3     # the version Cilium 1.20 documents for its Gateway API support
KIND_NETWORK=${KIND_NETWORK:-ai-platform-ci}
KIND_SUBNET=${KIND_SUBNET:-172.18.0.0/16}  # platform/cilium takes LoadBalancer addresses from 172.18.255.0/24
# Keep in sync with configs.cm."kustomize.buildOptions" in platform/argocd/base/values.yaml.
KUSTOMIZE_FLAGS="--enable-helm --load-restrictor LoadRestrictionsNone"

echo "== 1. kind cluster $CLUSTER on Docker network $KIND_NETWORK ($KIND_SUBNET)"
# The cluster gets its own Docker network with a fixed subnet, so the LoadBalancer IP pool
# committed in platform/cilium is valid on every machine and never collides with other kind
# clusters on the same host. kind honours KIND_EXPERIMENTAL_DOCKER_NETWORK for the network name.
if docker network inspect "$KIND_NETWORK" >/dev/null 2>&1; then
  have=$(docker network inspect "$KIND_NETWORK" --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}')
  case "$have" in
    *"$KIND_SUBNET"*) ;;
    *) echo "Docker network $KIND_NETWORK exists with subnet $have, expected $KIND_SUBNET"; exit 1 ;;
  esac
else
  docker network create --subnet "$KIND_SUBNET" "$KIND_NETWORK" >/dev/null
fi
export KIND_EXPERIMENTAL_DOCKER_NETWORK="$KIND_NETWORK"
if kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  echo "cluster exists, reusing it"
else
  kind create cluster --config "$HERE/kind-config.yaml"
fi
kubectl config use-context "$CONTEXT" >/dev/null

echo "== 2. Gateway API CRDs $GATEWAY_API_VERSION (Cilium: 'The below CRDs from Gateway API v1.6.3 must be installed')"
for crd in gatewayclasses gateways httproutes referencegrants grpcroutes backendtlspolicies tlsroutes; do
  kubectl apply --server-side -f "https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/$GATEWAY_API_VERSION/config/crd/standard/gateway.networking.k8s.io_$crd.yaml"
done

echo "== 3. Cilium $CILIUM_VERSION (kube-proxy replacement, Gateway API, Hubble, L2 announcements)"
# Kube-proxy-free docs: --set k8sServiceHost=${API_SERVER_IP} --set k8sServicePort=${API_SERVER_PORT}.
# With kind the API server is the control-plane container on the kind network.
API_SERVER_IP=$(docker inspect "$CLUSTER-control-plane" --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}')
helm upgrade --install cilium cilium --repo https://helm.cilium.io --version "$CILIUM_VERSION" \
  --namespace kube-system \
  --values "$HERE/cilium-values.yaml" \
  --set k8sServiceHost="$API_SERVER_IP" \
  --set k8sServicePort=6443
cilium status --wait --wait-duration 10m
kubectl wait --for=condition=Ready node --all --timeout=5m

echo "== 4. Argo CD, applied from the very overlay Argo CD will manage itself with"
kustomize build $KUSTOMIZE_FLAGS "$ROOT/platform/argocd/overlays/ci" | kubectl apply --server-side -f -
kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=10m
kubectl -n argocd rollout status deployment/argocd-repo-server --timeout=10m
kubectl -n argocd rollout status deployment/argocd-server --timeout=10m

if [ -n "${GITHUB_TOKEN:-}" ]; then
  echo "== 5. repository credentials (only needed while the repository is private)"
  # Argo CD declarative setup: a Secret labelled argocd.argoproj.io/secret-type=repository.
  # https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/#repositories
  kubectl -n argocd create secret generic repo-ai-platform-reference \
    --from-literal=type=git \
    --from-literal=url=https://github.com/blacksoxx/ai-platform-reference.git \
    --from-literal=username=x-access-token \
    --from-literal=password="$GITHUB_TOKEN" \
    --dry-run=client -o yaml \
    | kubectl label --local -f - argocd.argoproj.io/secret-type=repository -o yaml \
    | kubectl apply -f -
fi

echo "== 6. root Application"
kubectl apply -f "$HERE/root-app.yaml"

echo "== done; Argo CD is now applying apps/ci. Follow with: make ci-status, then make e2e"
echo "   Argo CD admin password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
