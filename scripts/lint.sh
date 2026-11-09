#!/bin/sh
# Static checks, the same locally (make lint) and in GitHub Actions (.github/workflows/ci.yml):
#   1. yamllint over the repository
#   2. kustomize build of every overlay, with the exact flags Argo CD uses, piped to kubeconform
#   3. the two overlays of a component must pin the same chart version
#   4. kyverno test over the policies
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

# Keep in sync with configs.cm."kustomize.buildOptions" in platform/argocd/base/values.yaml.
KUSTOMIZE_FLAGS="--enable-helm --load-restrictor LoadRestrictionsNone"
# Upstream CRD schemas for kubeconform; -ignore-missing-schemas covers CRDs not catalogued yet.
CRD_SCHEMAS='https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
KUBERNETES_VERSION=${KUBERNETES_VERSION:-1.36.0}
# Kinds whose catalogued schema lags behind the chart that renders them (group/version/Kind).
# nvidia.com ClusterPolicy: gpu-operator v26.7.2 sets dcgmExporter.serviceMonitor.scrapeTimeout,
# which the CRDs-catalog copy of the schema does not know yet. Kyverno's ClusterPolicy is unaffected.
KUBECONFORM_SKIP=${KUBECONFORM_SKIP:-nvidia.com/v1/ClusterPolicy}

fail=0

echo "== yamllint"
yamllint -c .yamllint . && echo "ok"

echo "== kustomize build + kubeconform"
for kz in $(find clusters platform apps tenants workloads policies dashboards alerts -name kustomization.yaml -not -path "*/charts/*" 2>/dev/null | sort); do
  dir=$(dirname "$kz")
  if ! rendered=$(kustomize build $KUSTOMIZE_FLAGS "$dir" 2>&1); then
    echo "FAIL  $dir (kustomize)"; echo "$rendered" | sed 's/^/      /' | head -20; fail=1; continue
  fi
  if printf '%s\n' "$rendered" | kubeconform -strict -ignore-missing-schemas -kubernetes-version "$KUBERNETES_VERSION" \
      -schema-location default -schema-location "$CRD_SCHEMAS" -skip "$KUBECONFORM_SKIP" \
      -summary -output text >/tmp/kubeconform.out 2>&1; then
    echo "ok    $dir  ($(grep -oE 'Valid: [0-9]+, Invalid: [0-9]+, Errors: [0-9]+, Skipped: [0-9]+' /tmp/kubeconform.out | head -1))"
  else
    echo "FAIL  $dir (kubeconform)"; sed 's/^/      /' /tmp/kubeconform.out | head -20; fail=1
  fi
done

echo "== chart versions consistent across overlays"
for comp in platform/*/; do
  [ -d "$comp/overlays" ] || continue
  n=$(grep -h '^    version:' "$comp"/overlays/*/kustomization.yaml 2>/dev/null | sed 's/#.*//' | sort -u | wc -l | tr -d ' ')
  if [ "$n" -gt 1 ]; then echo "FAIL  $comp overlays pin different chart versions"; fail=1; else echo "ok    $comp"; fi
done

if [ -d policies ]; then
  echo "== kyverno test"
  kyverno test policies && echo "ok"
fi

exit $fail
