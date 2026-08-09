# Module: openid-connect-zitadel

**Status:** draft · **Decisions:** [ADR 1](../../adr/0001-oidc-provider-zitadel.md),
[ADR 7](../../adr/0007-modules-receive-credentials.md),
[ADR 8](../../adr/0008-postgresql-is-external.md)

## Intent

Run one OIDC issuer for the lab, and publish its address. Nothing more.

The module does not know which services authenticate against it, does not register clients,
and does not hold client secrets. Those are registered out of band and delivered to
consumers as Secret references.

## Provisions

One Argo CD `ApplicationSet` ([ADR 5](../../adr/0005-modules-are-applicationsets.md)),
generating a single Application: the `zitadel` chart, pinned to `11.0.0-beta.4`, scaled to a
single replica, backed by the supplied PostgreSQL, with its masterkey read from an existing
Secret.

An `HTTPRoute` when `gateway` is set — Zitadel's console and its discovery document are the
one surface here that has to be reachable from outside. Native case per
[ADR 10](../../adr/0010-resources-delivered-via-chart.md): the chart's own
`gateway.httpRoute` values render it directly.

**Scraping.** When `metrics_enabled` is `true`, the chart's own `serviceMonitor.enabled` is
set, producing a `VMServiceScrape` via CRD conversion
([ADR 4](../../adr/0004-scrape-config-via-prometheus-crds.md)).

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

There is deliberately no client output. See [ADR 7](../../adr/0007-modules-receive-credentials.md).

## Acceptance criteria

```gherkin
Feature: An issuer, and only an issuer

  Scenario: The module publishes no client material
    Given the module has been applied
    When its outputs are enumerated
    Then none is named for a client
     And no output is marked sensitive because none carries a secret

  Scenario: A database is mandatory
    Given database is null
    When terraform plan runs
    Then it fails

  Scenario: The published issuer is the real one
    Given the module has been applied with a gateway
    When the discovery document is fetched from discovery_url
    Then its "issuer" field equals the issuer_url output

  Scenario: One replica
    Given the module has been applied
    When the Zitadel Deployment is inspected
    Then it has exactly one replica

  Scenario: The masterkey is never rendered
    Given a masterkey_secret_name is supplied
    When the Argo CD Application spec is read
    Then it references the Secret by name
     And the masterkey value does not appear in the rendered values
```

## Open items

- Install runs init and setup Jobs through Helm hooks, which Argo CD translates to its own
  hook semantics. Expect one round of sync-ordering trouble; `ServerSideApply=true` may be
  needed on the Application.
- Registering clients by hand means the redirect URIs are typed by a human. Hostnames are
  defined once as `root.hcl` locals so at least both sides read the same value.
- Revisit at roughly fifteen clients: a dedicated registration unit would not change this
  module's contract, only add a sibling.
