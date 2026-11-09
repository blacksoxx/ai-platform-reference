# Vault initialisation (lab)

The lab Vault (`platform/vault/overlays/lab`) is a standalone server with persistent storage.
Unlike the ci dev server, it starts sealed and uninitialised; an operator initialises it once
and configures what the platform expects. This is the manual counterpart of the ci Job in
`platform/vault/overlays/ci/configure-job.yaml`; the commands are the same, from the Vault
documentation of the Kubernetes auth method.

## 1. Initialise and unseal

```sh
kubectl -n vault exec -it vault-0 -- vault operator init -key-shares=1 -key-threshold=1 -format=json > vault-init.json
# Keep vault-init.json outside the repository and outside the cluster. It holds the unseal key and the root token.
kubectl -n vault exec -it vault-0 -- vault operator unseal "$(jq -r '.unseal_keys_b64[0]' vault-init.json)"
```

A single key share is a lab choice; production uses a threshold of several shares or auto-unseal.
After every restart of the Pod, Vault is sealed again until `operator unseal` runs.

## 2. Configure, as the ci Job does

```sh
export VAULT_TOKEN=$(jq -r .root_token vault-init.json)
v() { kubectl -n vault exec -i vault-0 -- env VAULT_TOKEN="$VAULT_TOKEN" vault "$@"; }

v auth enable kubernetes
v write auth/kubernetes/config kubernetes_host="https://kubernetes.default.svc:443"
v secrets enable -path=platform kv-v2
v policy write external-secrets - <<'HCL'
path "platform/data/*"     { capabilities = ["read"] }
path "platform/metadata/*" { capabilities = ["read", "list"] }
HCL
v write auth/kubernetes/role/external-secrets \
  bound_service_account_names=external-secrets \
  bound_service_account_namespaces=external-secrets \
  policies=external-secrets audience=vault ttl=1h
```

## 3. Seed the secrets the platform expects

```sh
v kv put platform/grafana admin-user=admin admin-password="$(openssl rand -base64 24)"
```

Every `ExternalSecret` in the repository names its Vault key; `grep -r 'remoteRef' platform
tenants workloads` lists them.

## 4. Verify

```sh
kubectl get clustersecretstore vault          # READY True
kubectl -n monitoring get externalsecret      # SecretSynced
```

## Rotation and recovery

Rotate a value with `v kv put`; External Secrets refreshes within `refreshInterval` (1 h) or on
`kubectl annotate externalsecret <name> force-sync=$(date +%s)`. If the volume is lost,
repeat this runbook; consumers restart with the new values.
