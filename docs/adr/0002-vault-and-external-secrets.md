# ADR 0002: Vault in-cluster behind External Secrets Operator

**Status**: accepted, 2026-11-09

## Context

No secret value may live in Git, and components (Grafana first) need credentials at deploy
time. The platform must run on a laptop without any external account. Options: an external
secrets manager (Infisical Cloud, a cloud provider's), Sealed Secrets, SOPS with age keys in
Git, or a self-hosted store inside the cluster.

## Decision

HashiCorp Vault runs in the cluster (`platform/vault`) and is the only secret store. External
Secrets Operator (`platform/external-secrets`) reads it through a `ClusterSecretStore` using
the Kubernetes auth method and materialises `ExternalSecret` resources into Kubernetes Secrets.
In ci Vault runs in dev mode and a Sync-hook Job configures auth, the `platform` KV v2 engine,
the read-only `external-secrets` role and the seed secrets. In lab Vault is a standalone server
with persistent storage, initialised once by the [runbook](../runbooks/vault-init.md).

## Consequences

- Self-contained: no cloud account, the same flow on a laptop and in the lab, and the operator
  learns Vault's auth model (policies, roles, token audiences) rather than a vendor's UI.
- Dev mode in ci means secrets are regenerated whenever the Vault Pod restarts; the Job is
  idempotent and re-runs on every sync of the Application, and consumers tolerate a rotation
  (Grafana re-reads its admin Secret on restart).
- Lab Vault needs a PersistentVolume; RKE2 ships no StorageClass, so storage is a site choice
  made before the lab bootstrap (setup-lab.md).
- Vault traffic inside the cluster is HTTP on the cluster network; enabling TLS with the
  platform CA is the next step on the security roadmap.
