# Set up the ci environment

The ci environment is the whole platform on a kind cluster, with simulated GPUs. It runs on a
laptop and on a GitHub runner the same way. Budget: about five minutes to bootstrap, fifteen
to twenty for every Application to be Healthy on the first run (images are pulled, the
inference model is downloaded), then the proofs.

## Prerequisites

| Tool | Version used in CI | Install |
|---|---|---|
| Docker | Docker Desktop or OrbStack, 12 GB for Docker | vendor |
| kind | 0.33.0 | `brew install kind` or the release binary |
| kubectl | 1.36.x | `brew install kubectl` |
| helm | 3.x or 4.x | `brew install helm` |
| kustomize | 5.8.3 | `brew install kustomize` |
| cilium CLI | v0.20.2 | `brew install cilium-cli` |

For `make lint` also: kubeconform 0.8.0, yamllint 1.38.0, kyverno CLI 1.19.2.

## Bring it up

```sh
make ci-up
```

What the bootstrap does, in order (`clusters/ci/bootstrap.sh`):

1. Creates a Docker network `ai-platform-ci` with the subnet `172.18.0.0/16` and a kind
   cluster on it (`clusters/ci/kind-config.yaml`): one control plane, two workers labelled
   for the fake GPU operator, no default CNI, no kube-proxy.
2. Builds `images/gpu-probe` for the node architecture and loads it into the nodes as `:dev`.
3. Applies the Gateway API v1.6.3 CRDs that Cilium 1.20 documents.
4. Installs Cilium 1.20.4 with `clusters/ci/cilium-values.yaml`: kube-proxy replacement
   (`k8sServiceHost` is the control-plane container's address), Gateway API, Hubble, L2
   announcements. Waits for `cilium status`.
5. Applies `platform/argocd/overlays/ci` with Kustomize and waits for Argo CD.
6. If `GITHUB_TOKEN` is set, creates the repository credential Secret (needed only while the
   repository is private).
7. Applies `clusters/ci/root-app.yaml`.

Then Argo CD takes over. Watch it:

```sh
make ci-status                   # Applications, sync and health
kubectl get pods -A | grep -vE 'Running|Completed'
```

Applications turn Healthy wave by wave; the slowest are the inference backend (model
download, about 490 MB) and Kubescape's first scan.

## Reach the UIs

The Gateway has the address `172.18.255.10`, announced with ARP on the kind Docker network.
Hostnames are nip.io names that resolve to it, so there is nothing to configure in DNS:

| | URL |
|---|---|
| Argo CD | https://argocd.172-18-255-10.nip.io |
| Grafana | https://grafana.172-18-255-10.nip.io |
| Hubble UI | https://hubble.172-18-255-10.nip.io |
| Vault | https://vault.172-18-255-10.nip.io |
| Inference | https://inference.172-18-255-10.nip.io |

Whether your machine can reach `172.18.255.10` depends on how Docker runs:

- Linux: the Docker bridge is on the host; the address is reachable directly.
- macOS with OrbStack: container networks are routed to the host; reachable directly.
- macOS with Docker Desktop: container networks are not routable from the host. Use a port
  forward to the Gateway's Service and the hostname in the Host header, which is also what the
  proofs do:

```sh
kubectl -n platform-gateway port-forward svc/cilium-gateway-platform 8443:443
curl -k --resolve grafana.172-18-255-10.nip.io:8443:127.0.0.1 https://grafana.172-18-255-10.nip.io:8443/login
```

The certificate chain is the platform's own. Trust it once:

```sh
kubectl -n cert-manager get secret platform-root-ca -o jsonpath='{.data.ca\.crt}' | base64 -d > platform-root-ca.crt
# macOS: add it to the login keychain, or pass --cacert platform-root-ca.crt to curl
```

Credentials:

```sh
# Argo CD, user admin
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
# Grafana, user admin, password seeded in Vault and delivered by External Secrets
kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d
# Vault (dev mode): token root
```

## Run the proofs

```sh
make e2e
```

`scripts/e2e.sh` waits until every Application is Synced and Healthy (`E2E_TIMEOUT`, default
1200 s), then runs each script in `scripts/e2e.d/` and reports ok or FAIL per proof. Each
script is self-contained and can be run alone:

```sh
KUBE_CONTEXT=kind-ai-platform-ci sh scripts/e2e.d/72-kai-queue.sh
```

Talk to the model:

```sh
curl -k https://inference.172-18-255-10.nip.io/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"ai-platform","messages":[{"role":"user","content":"Say hello"}],"max_tokens":32}'
```

## Work on it

The loop is: change a file, `make lint`, commit, push. Argo CD polls the repository every two
minutes in ci and applies the change; `make ci-status` shows it landing. There is no way to
apply a local, uncommitted change through Argo CD, which is the point.

To iterate on one component without waiting for Argo CD, render it and apply it directly, then
let Argo CD reconcile the committed version afterwards:

```sh
kustomize build --enable-helm --load-restrictor LoadRestrictionsNone platform/falco/overlays/ci | kubectl apply --server-side -f -
```

## Tear it down

```sh
make ci-down                       # deletes the kind cluster
docker network rm ai-platform-ci   # optional
```

## GitHub Actions

- `ci.yml` runs `make lint` on every push and pull request.
- `e2e.yml` runs the bootstrap and the proofs on a kind cluster in the runner, after pushes to
  `main` and on demand. Argo CD in that cluster tracks `main`, so pull requests are linted but
  not deployed.
- `images.yml` builds, pushes and signs `images/gpu-probe` when it changes.
