# Module: secret-manager-openbao

**Status:** draft · **Decisions:** [ADR 9](../../adr/0009-secret-delivery-openbao-eso.md)

## Intent

Store the lab's secrets, and deliver them into the namespaces that need them. Storage and
delivery are one capability here — [ADR 7](../../adr/0007-modules-receive-credentials.md)
has every other module reference a Secret by name, which is only true if something creates
that Secret.

## Provisions

Two Argo CD Applications:

| Application | Chart | Role |
| --- | --- | --- |
| `openbao` | `openbao` | stores secrets, seals and unseals |
| `external-secrets` | `external-secrets` | materialises Secrets from OpenBao |

Plus a `ClusterSecretStore` addressing OpenBao, which is what makes every
`secret_name` elsewhere in this repo resolvable.

## Inputs

```hcl
seal = {
  type = "shamir"     # or "pkcs11"
  # pkcs11 requires the kms plugin and a token on the host
}

storage_size = "2Gi"
gateway      = null   # the UI is not exposed by default, and should stay that way
```

## Outputs

| Output | Value |
| --- | --- |
| `address` | in-cluster address of OpenBao |
| `cluster_secret_store_name` | name consumers' `ExternalSecret`s reference |

## Acceptance criteria

```gherkin
Feature: Secrets are stored and delivered

  Scenario: Delivery works end to end
    Given OpenBao is unsealed
     And a secret exists at a known path
    When an ExternalSecret referencing cluster_secret_store_name is created
    Then a Kubernetes Secret appears in the target namespace
     And its keys match the ones requested

  Scenario: Sealed means unavailable, loudly
    Given OpenBao is sealed
    When an ExternalSecret is reconciled
    Then it reports a failure condition
     And no empty or partial Secret is created

  Scenario: The UI is not reachable by default
    Given gateway is null
    When HTTPRoutes in the namespace are listed
    Then none exist

  Scenario: Restart behaviour is known
    Given the seal type in use
    When the OpenBao pod restarts
    Then it either unseals unattended, or reports sealed and waits
     And which of those happens is the documented consequence of the chosen seal
```

## Open items

- **The seal is undecided.** TPM 2.0 via the PKCS#11 plugin is the only option that is both
  unattended and not self-defeating on a single node; Shamir with manual unsealing is the
  honest fallback. SoftHSM2 buys convenience only. See
  [ADR 9](../../adr/0009-secret-delivery-openbao-eso.md).
- Bootstrap ordering: OpenBao must be unsealed and populated before Zitadel's masterkey
  Secret can exist, and Zitadel will not start without it.
- Backup of OpenBao's storage is out of scope, which is a real gap: losing it loses every
  credential the rest of the platform references.
