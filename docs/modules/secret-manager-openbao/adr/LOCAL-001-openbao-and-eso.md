# LOCAL-001. Secret delivery: OpenBao plus External Secrets Operator

**Status:** accepted · **Scope:** module — `secret-manager-openbao` · **Date:** 2026-08-05

## Context

[ADR 007](../../../adr/007-modules-receive-credentials.md) has every module receive a Secret
*name* rather than a secret value. That only works if something puts the Secret in the right
namespace.

Separately, the lab needs somewhere to keep secrets that survives a rebuild and is not a
file in git.

## Decision

`secret-manager-openbao` deploys **OpenBao and the External Secrets Operator** together.
OpenBao stores; ESO materialises. A `ClusterSecretStore` points at OpenBao and an
`ExternalSecret` per consumer produces the Secret that `var.database` and `var.oidc`
reference.

OpenBao rather than HashiCorp Vault.

## Rationale

- Storage without delivery is useless here, and delivery without storage is just kubectl.
  Two units that are meaningless apart belong in one module.
- OpenBao is Apache-2.0 under the Linux Foundation; Vault is BUSL.
- **PKCS#11 seal is open source in OpenBao and Enterprise-only in Vault.** That is the only
  door to a self-hosted root of trust without a cloud KMS, and it is available as a `kms`
  plugin from OpenBao 2.6.

## Consequences

- **Unsealing is unsolved**, and choosing PKCS#11 as the reason to prefer OpenBao does not by
  itself pick a seal. That decision is [LOCAL-002](LOCAL-002-openbao-seal.md), still
  `proposed`.
- Bootstrapping is ordered: OpenBao must be unsealed and populated before the Secrets it
  holds exist, and before the workloads that reference them start. This is a consequence of
  choosing ESO, not a rule the platform enforces — a module declares the Secret it needs and
  is indifferent to when it appears
  ([ADR 007](../../../adr/007-modules-receive-credentials.md)). Satisfying it is operational.
- Each environment gets its own OpenBao ([ADR 011](../../../adr/011-environments-are-clusters.md)),
  so every consequence in this list — the seal, the backup gap, the bootstrap ordering — is
  paid once per environment rather than once.
- ESO adds a CRD set and a controller.
- **Backup of OpenBao's storage is out of scope**, and [REQ-04](../../../requirements.md)
  leans on it. Losing that storage loses every credential the rest of that environment
  references. This gap is independent of which seal is chosen.
