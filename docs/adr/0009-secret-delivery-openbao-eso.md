# 9. Secret delivery: OpenBao plus External Secrets Operator

**Status:** accepted · **Date:** 2026-08-05

## Context

[ADR 7](0007-modules-receive-credentials.md) has every module receive a Secret *name* rather
than a secret value. That only works if something puts the Secret in the right namespace.

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

- **Unsealing on a single node is unsolved and must be chosen deliberately.** Options, and
  none is free:
  - *TPM 2.0 via PKCS#11* — real hardware root of trust, unattended across reboots. The key
    is bound to that machine, so node death means restore from backup, not migrate.
  - *SoftHSM2* — the key sits on disk beside what it protects. Buys unattended restarts and
    nothing else. Convenience, not security.
  - *Transit seal from a second OpenBao* — moves the problem to a second instance that still
    needs unsealing. Only worth it if that one lives somewhere more durable.
  - *Shamir, unsealed by hand* — honest, and fine at monthly reboots.
- Bootstrapping is ordered: OpenBao first, then the Secrets it holds, then the workloads that
  reference them.
- ESO adds a CRD set and a controller.
