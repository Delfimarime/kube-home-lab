# Module: audit-management-auditum

**Status:** draft, **blocked on an open question** ·
**Satisfies:** [REQ-07](../../requirements.md) — which is itself unresolved ·
**Decisions:** [ADR 004](../../adr/004-scrape-config-via-prometheus-crds.md),
[ADR 005](../../adr/005-modules-are-applicationsets.md),
[ADR 007](../../adr/007-modules-receive-credentials.md),
[ADR 008](../../adr/008-postgresql-is-external.md),
[ADR 010](../../adr/010-resources-delivered-via-chart.md),
[ADR 014](../../adr/014-exposed-does-not-mean-authorized.md),
[ADR 016](../../adr/016-metrics-is-the-fourth-input.md)

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
Application at. That also gives it a way to receive OpenTofu-computed values — host, port,
secret name — which static manifests never had:

| Resource | Detail |
| --- | --- |
| `ConfigMap` | `auditum.yaml`: store type postgres, host, port, database, username |
| `Deployment` | 2 replicas, `RollingUpdate`; password from `secretKeyRef` |
| `PodDisruptionBudget` | `maxUnavailable: 1` |
| `Service` | 8080 HTTP, 9090 gRPC |
| `HTTPRoute` | when `gateway` is set |
| scrape resource | hand-authored (no chart to flip a `serviceMonitor.enabled` switch on — [ADR 004](../../adr/004-scrape-config-via-prometheus-crds.md)), when `metrics.enabled` is `true` |

The database password is supplied as `AUDITUM_STORE_POSTGRES_PASSWORD` from a `secretKeyRef`,
never written into the ConfigMap. Auditum's environment variables are prefixed `AUDITUM_`
and override config-file keys, which is what makes this possible.

## Inputs

```hcl
database = {          # required; SQLite is not used
  host_port     = "postgres.example:5432"
  database_name = "auditum"
  secret_name   = null           # null renders it here, empty; set names an existing one
}

gateway = null        # default: not exposed. See the security note below.
                      # database.secret_name null renders the Secret here, empty — ADR 022.

metrics = { enabled = false }   # a root variable, declared once — ADR 016
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
and `log`. **It has no authentication section, and no UI.** It is therefore the second workload
here that cannot answer for a request once it arrives, and
[ADR 014](../../adr/014-exposed-does-not-mean-authorized.md) is the decision that governs it.

**It is not the same case as the OTLP ingest endpoint, and the difference is the whole point.**
That surface is write-only, so an unauthenticated caller costs disk and data quality. This one
is read *and* write: Auditum's HTTP API queries records as well as accepting them, so exposing
it without authorization discloses the audit trail and lets anything on the network forge
entries into it — a record that looks authoritative and is not, which is worse than no record.
ADR 014's rationale says explicitly that an unauthenticated read surface would make that
decision indefensible; this is that surface.

`gateway` therefore defaults to `null` and should stay there. If something outside the cluster
genuinely needs to write records, the mechanism now exists and needs no module change: point
`gateway.section_name` at the environment's mTLS listener, so a caller must present the client
certificate
[`certificate-management-cert-manager`](../certificate-management-cert-manager/README.md)
issues. That authenticates a *machine*, not a person, and Auditum still applies no
authorization of its own — acceptable for a write path, and still not enough to expose the
query path to anything but a trusted host.

## Acceptance criteria

```gherkin
Feature: Auditum stores audit records durably

  @plan
  Scenario: [AUD-01] PostgreSQL is mandatory
    Given database is null
    When tofu plan runs
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
