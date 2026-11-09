#!/bin/sh
# Bootstrap the lab environment, one role at a time, on the node itself. Each step is what
# docs/setup-lab.md describes; the script only keeps the commands and files in one place.
#
#   sudo clusters/lab/bootstrap.sh server           on the control-plane node
#   sudo clusters/lab/bootstrap.sh agent-nvidia     on the DGX Spark
#   sudo clusters/lab/bootstrap.sh agent-amd        on the Ryzen AI Max+ box
#        clusters/lab/bootstrap.sh argocd           from a machine with the kubeconfig
#
# Before "server": write the join token to /etc/rancher/rke2/config.yaml.d/token.yaml.
# Before "agent-*": the same file on the agent, with the token read from the server's
# /var/lib/rancher/rke2/server/node-token (RKE2 quick start).
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
RKE2_VERSION=v1.36.6+rke2r1          # github.com/rancher/rke2 releases, checked 2026-11-09
GATEWAY_API_VERSION=v1.6.3           # the version Cilium 1.20 documents for its Gateway API support
KUSTOMIZE_FLAGS="--enable-helm --load-restrictor LoadRestrictionsNone"

role=${1:-}
case "$role" in
  server)
    # RKE2 quick start: curl -sfL https://get.rke2.io | sh -, then enable and start the service.
    # The installer honours INSTALL_RKE2_VERSION (get.rke2.io, header comment) to pin a release.
    mkdir -p /etc/rancher/rke2 /var/lib/rancher/rke2/server/manifests
    cp "$HERE/rke2/server.yaml" /etc/rancher/rke2/config.yaml
    cp "$HERE/rke2/manifests/rke2-cilium-config.yaml" /var/lib/rancher/rke2/server/manifests/
    [ -f /etc/rancher/rke2/config.yaml.d/token.yaml ] || { echo "write the token to /etc/rancher/rke2/config.yaml.d/token.yaml first"; exit 1; }
    curl -sfL https://get.rke2.io | INSTALL_RKE2_VERSION="$RKE2_VERSION" sh -
    systemctl enable rke2-server.service
    systemctl start rke2-server.service
    echo "kubeconfig: /etc/rancher/rke2/rke2.yaml   node token: /var/lib/rancher/rke2/server/node-token"
    ;;
  agent-nvidia|agent-amd)
    mkdir -p /etc/rancher/rke2
    cp "$HERE/rke2/$role.yaml" /etc/rancher/rke2/config.yaml
    [ -f /etc/rancher/rke2/config.yaml.d/token.yaml ] || { echo "write the token to /etc/rancher/rke2/config.yaml.d/token.yaml first"; exit 1; }
    # RKE2 quick start: curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE="agent" sh -
    curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE=agent INSTALL_RKE2_VERSION="$RKE2_VERSION" sh -
    systemctl enable rke2-agent.service
    systemctl start rke2-agent.service
    ;;
  argocd)
    # From the Mac, with KUBECONFIG pointing at the lab cluster.
    echo "== Gateway API CRDs $GATEWAY_API_VERSION"
    for crd in gatewayclasses gateways httproutes referencegrants grpcroutes backendtlspolicies tlsroutes; do
      kubectl apply --server-side -f "https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/$GATEWAY_API_VERSION/config/crd/standard/gateway.networking.k8s.io_$crd.yaml"
    done
    echo "== Argo CD from its lab overlay"
    kustomize build $KUSTOMIZE_FLAGS "$ROOT/platform/argocd/overlays/lab" | kubectl apply --server-side -f -
    kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=10m
    kubectl -n argocd rollout status deployment/argocd-server --timeout=10m
    echo "== root Application"
    kubectl apply -f "$HERE/root-app.yaml"
    ;;
  *)
    echo "usage: $0 server | agent-nvidia | agent-amd | argocd"; exit 1 ;;
esac
