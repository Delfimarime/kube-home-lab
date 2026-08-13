# Module: audit-management-auditum

**Status:** draft, **blocked on an open question** ·
**Satisfies:** [REQ-07](../../requirements.md) — which is itself unresolved ·
**Decisions:** [ADR 007](../../adr/007-modules-receive-credentials.md),
[ADR 008](../../adr/008-postgresql-is-external.md)

## Intent

Run [Auditum](https://github.com/auditumio/auditum) so applications have somewhere to write
audit records and somewhere to query them from.

## Blocking question

**What is this auditing?** Two different systems get called "audit" and only one of them is
Auditum:

- *Application audit trails* — your own services recording "user X changed Y". Auditum's
  actual job. Requires an application that writes to it; none exists yet.
- *Kubernetes API audit logs* — who deleted what in the cluster. That is an API-server flag on
  k3s (`--kube-apiserver-arg=audit-log-path=…`) producing a log stream. Auditum has no ingester
  for it and would be the wrong tool.

Everything below assumes the first. If it is the second, this module should not exist.

## Provisions

Auditum publishes no Helm chart — the documentation says one is "currently in development."
Per [ADR 010](../../adr/010-resources-delivered-via-chart.md), this is the **custom case**: a
chart local to this repository, authored from scratch, that this module's single-entry
`ApplicationSet` ([ADR 005](../../adr/005-modules-are-applicationsets.md)) points its generated
Application at. That also gives it a way to receive Terraform-computed values — host, port,
secret name — which static manifests never had:

| Resource | Detail |
| --- | --- |
| `ConfigMap` | `auditum.yaml`: store type postgres, host, port, database, username |
| `Deployment` | 2 replicas, `RollingUpdate`; password from `secretKeyRef` |
| `PodDisruptionBudget` | `maxUnavailable: 1` |
| `Service` | 8080 HTTP, 9090 gRPC |
| `HTTPRoute` | when `gateway` is set |
| scrape resource | hand-authored (no chart to flip a `serviceMonitor.enabled` switch on — [ADR 004](../../adr/004-scrape-config-via-prometheus-crds.md)), when `metrics_enabled` is `true` |

The database password is supplied as `AUDITUM_STORE_POSTGRES_PASSWORD` from a `secretKeyRef`,
never written into the ConfigMap. Auditum's environment variables are prefixed `AUDITUM_`
and override config-file keys, which is what makes this possible.

## Inputs

```hcl
database = {          # required; SQLite is not used
  host_port     = "postgres.example:5432"
  database_name = "auditum"
  secret_name   = "auditum-db"
}

gateway = null        # default: not exposed. See the security note below.

metrics_enabled = false   # set from observability-grafana-lgtm's `metrics_enabled` output
```

There is no `oidc` input, because Auditum has no authentication to delegate.

## Outputs

Addresses only, per [ADR 007](../../adr/007-modules-receive-credentials.md). Both are
in-cluster; there is deliberately no output for an external URL, because `gateway` defaults
to `null` and should stay there — see the security note below.

| Output | Used by |
| --- | --- |
| `http_endpoint` | applications writing or querying records over HTTP (8080) |
| `grpc_endpoint` | applications writing records over gRPC (9090) |

## Security note

Auditum's default configuration file has sections for `store`, `http`, `grpc`, `telemetry`
and `log`. **It has no authentication section, and no UI.** Exposing it through the Gateway
publishes an unauthenticated write API for audit records — a record anything on the network
can forge, which is worse than no record at all because it looks authoritative.

`gateway` therefore defaults to `null`, and should stay that way until either:

- something outside the cluster genuinely needs to write records, and
- oauth2-proxy fronts the HTTP port, with gRPC left internal.

## Acceptance criteria

```gherkin
Feature: Auditum stores audit records durably

  @plan
  Scenario: [AUD-01] PostgreSQL is mandatory
    Given database is null
    When terraform plan runs
    Then it fails
     And SQLite is never selected as a fallback

  @cluster
  Scenario: [AUD-02] The password never reaches a ConfigMap
    Given the module has been applied
    When the auditum ConfigMap is read
    Then it contains host, port, database name and username
     And it does not contain the password

  @cluster
  Scenario: [AUD-03] A node can still be drained
    Given 2 replicas and a PodDisruptionBudget of maxUnavailable 1
    When the node is drained
    Then eviction proceeds rather than blocking indefinitely

  @cluster
  Scenario: [AUD-04] Not exposed by default
    Given gateway is null
    When HTTPRoutes in the namespace are listed
    Then none exist

  @cluster
  Scenario: [AUD-05] Records survive a restart
    Given a record has been written through the HTTP API
    When every Auditum pod is deleted and rescheduled
    Then the record is still queryable
```

## Open items

- The blocking question above.
- Confirm Auditum's metrics endpoint — the project advertises built-in metrics, but the port
  and path are not yet verified, and the scrape resource needs both.
- Two replicas on a single node buys zero-downtime deploys, not availability. Both die with
  the node. Stated so nobody later mistakes the PDB for resilience.
- Upstream is small: 78 stars, Apache-2.0, last pushed 2026-04-30. Watch for the Helm chart
  landing, at which point the in-repo manifests can be retired.
