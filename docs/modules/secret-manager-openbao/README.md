# Module: secret-manager-openbao

**Status:** draft ·
**Satisfies:** [REQ-04, REQ-05, REQ-06](../../requirements.md) ·
**Decisions:** [LOCAL-001](adr/LOCAL-001-openbao-and-eso.md),
[LOCAL-002](adr/LOCAL-002-openbao-seal.md) (proposed),
[ADR 007](../../adr/007-modules-receive-credentials.md)

## Intent

Store an environment's secrets, and deliver them into the namespaces that need them. Storage
and delivery are one capability here — [ADR 007](../../adr/007-modules-receive-credentials.md)
has every other module reference a Secret by name, which is only true if something creates
that Secret.

One OpenBao per environment ([ADR 011](../../adr/011-environments-are-clusters.md)). Secrets
do not cross environments, and neither does the seal.

## Provisions

One Argo CD `ApplicationSet` ([ADR 005](../../adr/005-modules-are-applicationsets.md)),
generating two Applications:

| Application | Chart | Role |
| --- | --- | --- |
| `openbao` | `openbao` | stores secrets, seals and unseals |
| `external-secrets` | `external-secrets` | materialises Secrets from OpenBao |

Plus a `ClusterSecretStore` addressing OpenBao, which is what makes every
`secret_name` elsewhere in this repo resolvable.

If `gateway` is ever set, it's the native case per
[ADR 010](../../adr/010-resources-delivered-via-chart.md): the chart's own
`server.gateway.httpRoute` values render the route — though the UI should stay unexposed (see
`gateway` below).

**Scraping.** When `metrics_enabled` is `true`, the chart's own `serviceMonitor.enabled` is
set, producing a `VMServiceScrape` via CRD conversion
([ADR 004](../../adr/004-scrape-config-via-prometheus-crds.md)).

## Inputs

```hcl
seal = {
  type = "shamir"     # or "pkcs11"
  # pkcs11 requires the kms plugin and a token on the host
}

storage_size     = "2Gi"
gateway          = null   # the UI is not exposed by default, and should stay that way
metrics_enabled  = false  # set from observability-victoria-metrics's `metrics_enabled` output
```

## Outputs

| Output | Value |
| --- | --- |
| `address` | in-cluster address of OpenBao |
| `cluster_secret_store_name` | name consumers' `ExternalSecret`s reference |

## Acceptance criteria

```gherkin
Feature: Secrets are stored and delivered

  @cluster
  Scenario: [SEC-01] Delivery works end to end
    Given OpenBao is unsealed
     And a secret exists at a known path
    When an ExternalSecret referencing cluster_secret_store_name is created
    Then a Kubernetes Secret appears in the target namespace
     And its keys match the ones requested

  @cluster
  Scenario: [SEC-02] Sealed means unavailable, loudly
    Given OpenBao is sealed
    When an ExternalSecret is reconciled
    Then it reports a failure condition
     And no empty or partial Secret is created

  @cluster
  Scenario: [SEC-03] The UI is not reachable by default
    Given gateway is null
    When HTTPRoutes in the namespace are listed
    Then none exist

  @cluster
  Scenario: [SEC-04] Restart behaviour is known
    Given the seal type in use
    When the OpenBao pod restarts
    Then it either unseals unattended, or reports sealed and waits
     And which of those happens is the documented consequence of the chosen seal
```

## Open items

- **The seal is undecided**, and it is the highest-stakes open item here — see
  [LOCAL-002](adr/LOCAL-002-openbao-seal.md). With one OpenBao per environment, whatever is
  chosen is operated once per environment.
- OpenBao must be unsealed and populated before the Secrets it holds exist, and before the
  workloads referencing them start. That is a property of this module, not a rule the
  platform enforces: a consumer declares the Secret it needs and is indifferent to when it
  appears ([ADR 007](../../adr/007-modules-receive-credentials.md)). Satisfying it is
  operational.
- Backup of OpenBao's storage is out of scope, which is a real gap: losing it loses every
  credential the rest of that environment references.
