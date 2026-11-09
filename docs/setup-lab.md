# Set up the lab

The lab is the platform on real hardware: an RKE2 cluster whose control plane runs on a small
x86 box and whose GPU nodes are an NVIDIA DGX Spark (GB10, arm64) and an AMD Ryzen AI Max+
"Strix Halo" machine (amd64). It is driven by the same repository as ci, from `apps/lab/`.

The procedure below is what `clusters/lab/bootstrap.sh` automates per role. Read it once in
full: a few values are site-specific and must be set before anything is installed.

## 0. Before you start

**Site values to set in Git**

| What | Where | Why |
|---|---|---|
| Control-plane name or address | `clusters/lab/rke2/server.yaml` (`tls-san`), `agent-nvidia.yaml` and `agent-amd.yaml` (`server:`) | API certificate names and the agents' join target |
| LoadBalancer pool | `platform/cilium/overlays/lab/lb-ip-pool.yaml` | the Gateway's address; must be a free range on the lab network. The committed value is a documentation range that routes nowhere |
| Node interfaces | `platform/cilium/overlays/lab/l2-announcement-policy.yaml` | the interface names that answer ARP for the Gateway (`ip -br link` on each node) |
| Hostnames | `platform/gateway/overlays/lab/routes/*.yaml` | `*.lab.ai-platform.local` by default; point them at the Gateway address in your DNS or `/etc/hosts` |
| Storage | see "Storage" below | Vault (lab) and vCluster ask for a PersistentVolumeClaim |

**Hardware prerequisites**

- Spark: DGX OS with the NVIDIA driver and the NVIDIA Container Toolkit (both preinstalled).
  Check with `scripts/hardware/check-nvidia-node.sh`: it runs the probe and NVIDIA's CUDA
  sample in containers over ssh and removes everything afterwards. No other Kubernetes
  distribution may be running on the node (RKE2 and k3s both use `/run/k3s/containerd`).
- Halo: Linux with the `amdgpu` kernel driver and Docker, `/dev/kfd` and `/dev/dri` present.
  Check with `scripts/hardware/check-amd-node.sh`.
- Control plane: any x86 box with 4 CPUs and 8 GB free; nothing else listening on 6443 and 9345.
- All three reach each other on one network (the lab LAN or a mesh VPN); the Gateway address
  is announced with ARP, so the operator's machine must be on the same L2 segment or route to it.

## 1. Control plane

On the control-plane node:

```sh
sudo mkdir -p /etc/rancher/rke2/config.yaml.d
sudo sh -c 'printf "token: %s\n" "$(openssl rand -hex 32)" > /etc/rancher/rke2/config.yaml.d/token.yaml'
sudo clusters/lab/bootstrap.sh server
```

The script copies `clusters/lab/rke2/server.yaml` to `/etc/rancher/rke2/config.yaml`
(Cilium as CNI, kube-proxy disabled, no packaged ingress controller, RKE2's Gateway API CRDs
disabled) and the Cilium `HelmChartConfig` to `/var/lib/rancher/rke2/server/manifests/`, then
installs RKE2 `v1.36.6+rke2r1` with the install script (`INSTALL_RKE2_VERSION`) and starts
`rke2-server`. Kubeconfig: `/etc/rancher/rke2/rke2.yaml`; join token for the agents:
`/var/lib/rancher/rke2/server/node-token`.

Copy the kubeconfig to your machine, replace `127.0.0.1` with the control-plane address, and
check:

```sh
kubectl get nodes
kubectl -n kube-system get pods -l k8s-app=cilium
```

## 2. GPU agents

On the Spark (NVIDIA) and on the Halo (AMD), with the token from the server:

```sh
sudo mkdir -p /etc/rancher/rke2/config.yaml.d
sudo sh -c 'printf "token: %s\n" "<node-token>" > /etc/rancher/rke2/config.yaml.d/token.yaml'
sudo clusters/lab/bootstrap.sh agent-nvidia     # Spark
sudo clusters/lab/bootstrap.sh agent-amd        # Halo
```

Each agent config sets the vendor label `ai-platform.io/gpu=<vendor>` and the taint
`ai-platform.io/gpu=<vendor>:NoSchedule`. Platform services avoid GPU nodes; GPU workloads
select and tolerate them.

**NVIDIA runtime for RKE2's containerd.** The GPU Operator is installed with the driver and
toolkit components disabled, so the host's toolkit must configure RKE2's own containerd. The
RKE2 documentation for GPU operators sets the toolkit's `CONTAINERD_SOCKET` to
`/run/k3s/containerd/containerd.sock` when the toolkit component is enabled; with it disabled,
verify on the Spark after the join that containerd knows the runtime and that CDI specs are
present (`ls /etc/cdi /var/run/cdi`), and if not, enable the toolkit component in
`platform/nvidia-gpu-operator/overlays/lab/values.yaml` with that socket. This is the one
step of the lab that is validated on the hardware, not by the repository.

## 3. Argo CD and the platform

From your machine, with `KUBECONFIG` pointing at the lab:

```sh
clusters/lab/bootstrap.sh argocd
```

This applies the Gateway API v1.6.3 CRDs, `platform/argocd/overlays/lab` and
`clusters/lab/root-app.yaml`. Argo CD then applies `apps/lab/` in waves; `kubectl get
applications -n argocd` shows the progress. Differences from ci:

- the NVIDIA GPU Operator (`platform/nvidia-gpu-operator/overlays/lab`) and the AMD device
  plugin and metrics exporter replace the fake GPU operator;
- `inference` runs vLLM on the Spark and llama.cpp (ROCm) on the Halo, both serving
  Qwen2.5-7B-Instruct as `ai-platform`; the first start downloads the weights
  (about 15 GB for vLLM, 4.7 GB for the GGUF);
- Vault is a standalone server that must be initialised once: [runbooks/vault-init.md](runbooks/vault-init.md)
  covers `vault operator init`, unsealing, the Kubernetes auth method, the `platform` KV engine,
  the `external-secrets` role and the first secrets.

## 4. Verify

```sh
KUBE_CONTEXT=<lab context> E2E_TIMEOUT=3600 scripts/e2e.sh
```

The same proofs as ci, with real GPUs behind them; in addition:

```sh
kubectl apply -k workloads/gpu-probe/overlays/lab-nvidia && kubectl -n workloads logs job/gpu-probe-nvidia
kubectl apply -k workloads/gpu-probe/overlays/lab-amd    && kubectl -n workloads logs job/gpu-probe-amd
curl -k https://inference.lab.ai-platform.local/v1/chat/completions -H 'Content-Type: application/json' \
  -d '{"model":"ai-platform","messages":[{"role":"user","content":"Which GPU answered?"}]}'
```

Grafana's GPU folder shows DCGM metrics for the Spark; the inference dashboard shows which
backend answered.

## Storage

RKE2 ships no StorageClass. The lab overlays that need a volume (`platform/vault`,
the tenants' vClusters) leave `storageClass` at the cluster default. Add a provisioner of your
choice as a platform component before bootstrapping the lab, or set `persistence` off in those
overlays; the choice is deliberately not made here (see [ADR 0002](adr/0002-vault-and-external-secrets.md)).

## Tear down

On each node: `rke2-uninstall.sh` (server) or `rke2-agent-uninstall.sh` (agents), installed by
the RKE2 install script. On the Spark, that returns the machine to DGX OS with Docker only.
