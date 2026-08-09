# Module: openid-connect-zitadel

**Status:** draft ·
**Satisfies:** [REQ-01, REQ-09, REQ-10](../../requirements.md) ·
**Decisions:** [LOCAL-001](adr/LOCAL-001-oidc-provider-zitadel.md),
[ADR 007](../../adr/007-modules-receive-credentials.md),
[ADR 008](../../adr/008-postgresql-is-external.md),
[ADR 011](../../adr/011-environments-are-clusters.md)

## Intent

Run one OIDC issuer for the environment, and publish its address. Nothing more.

One issuer *per environment* — each cluster runs its own
([ADR 011](../../adr/011-environments-are-clusters.md)), so accounts do not carry between
them.

The module does not know which services authenticate against it, does not register clients,
and does not hold client secrets. Those are registered out of band and delivered to
consumers as Secret references.

## Provisions

One Argo CD `ApplicationSet` ([ADR 005](../../adr/005-modules-are-applicationsets.md)),
generating a single Application: the `zitadel` chart, pinned to `11.0.0-beta.4`, scaled to a
single replica, backed by the supplied PostgreSQL, with its masterkey read from an existing
Secret.

An `HTTPRoute` when `gateway` is set — Zitadel's console and its discovery document are the
one surface here that has to be reachable from outside. Native case per
[ADR 010](../../adr/010-resources-delivered-via-chart.md): the chart's own
`gateway.httpRoute` values render it directly.

**Scraping.** When `metrics_enabled` is `true`, the chart's own `serviceMonitor.enabled` is
set, producing a `VMServiceScrape` via CRD conversion
([ADR 004](../../adr/004-scrape-config-via-prometheus-crds.md)).

**Prerequisites.** A PostgreSQL database and a masterkey Secret must exist. This module
declares both as inputs and is indifferent to who creates them or when
([ADR 007](../../adr/007-modules-receive-credentials.md)).

## Inputs

```hcl
database = {            # required
  host_port     = "postgres.example:5432"
  database_name = "zitadel"
  secret_name   = "zitadel-db"
  username_key  = "username"
  password_key  = "password"
  sslmode       = "require"
}

gateway = {             # required in practice: an unreachable issuer is useless
  name         = "traefik"
  namespace    = "kube-system"
  hostname     = "id.lab.internal"
}

masterkey_secret_name = "zitadel-masterkey"

metrics_enabled = false   # set from observability-victoria-metrics's `metrics_enabled` output
```

## Outputs

| Output | Value |
| --- | --- |
| `issuer_url` | `https://<hostname>` |
| `discovery_url` | `https://<hostname>/.well-known/openid-configuration` |

There is deliberately no client output. See
[ADR 007](../../adr/007-modules-receive-credentials.md).

## Acceptance criteria

```gherkin
Feature: An issuer, and only an issuer

  @plan
  Scenario: [OIDC-01] The module publishes no client material
    Given the module has been applied
    When its outputs are enumerated
    Then none is named for a client
     And no output is marked sensitive because none carries a secret

  @plan
  Scenario: [OIDC-02] A database is mandatory
    Given database is null
    When terraform plan runs
    Then it fails

  @cluster
  Scenario: [OIDC-03] The published issuer is the real one
    Given the module has been applied with a gateway
    When the discovery document is fetched from discovery_url
    Then its "issuer" field equals the issuer_url output

  @cluster
  Scenario: [OIDC-04] One replica
    Given the module has been applied
    When the Zitadel Deployment is inspected
    Then it has exactly one replica

  @cluster
  Scenario: [OIDC-05] The masterkey is never rendered
    Given a masterkey_secret_name is supplied
    When the Argo CD Application spec is read
    Then it references the Secret by name
     And the masterkey value does not appear in the rendered values
```

## Open items

- Install runs init and setup Jobs through Helm hooks, which Argo CD translates to its own
  hook semantics. Expect one round of sync-ordering trouble; `ServerSideApply=true` may be
  needed on the Application.
- Registering clients by hand means the redirect URIs are typed by a human, once per
  environment. Hostnames are defined once in each environment's `env.hcl` so at least both
  sides read the same value ([ADR 011](../../adr/011-environments-are-clusters.md)).
- Revisit at roughly fifteen clients: a dedicated registration unit would not change this
  module's contract, only add a sibling.
