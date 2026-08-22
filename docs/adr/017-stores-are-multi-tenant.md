# 017. The stores are multi-tenant, and the caller names its tenant

**Status:** accepted · **Scope:** platform · **Date:** 2026-08-15

## Context

The three telemetry stores ran single-tenant: Mimir with `multitenancy_enabled: false`, Loki with
`auth_enabled: false`, Tempo the same. Everything written landed in one anonymous tenant.

Two things made that the wrong default.

**Nothing bounded what a writer could consume.**
[ADR 014](014-exposed-does-not-mean-authorized.md) accepted an unauthenticated ingest endpoint
on the grounds that the failure mode is a full volume rather than a leak — while naming no
mechanism that bounds the volume. Per-tenant ingestion limits are that mechanism, and they
require tenants. This is what [REQ-15](../requirements.md) now asks for.

**Switching it on later is a migration.** Everything written while multitenancy is off belongs
to the anonymous tenant. Turning it on afterwards means moving blocks or abandoning history.
Turning it on now costs a header in a few configuration files.

What that leaves is where the tenant comes from. Three shapes were real: derive it from the
client certificate presented at the Gateway; stamp it per ingest path, so it describes how data
arrived rather than who sent it; or take it from the caller and believe them.

## Decision

**Multitenancy is on in all three stores**, and a per-environment `tenants` value carries limits
and retention per tenant per signal.

**The tenant comes from the caller's `X-Scope-OrgID` and nothing validates it.** Certificates
and tenancy are orthogonal: the Gateway's client certificate says a caller may write, and the
header says where. Neither constrains the other.

**The collector propagates the header rather than replacing it**, and only where a request
exists to carry one:

| Path | Destination | Tenant |
| --- | --- | --- |
| scraped metrics, tailed logs, operator objects | the collector's built-in destinations | static, from `default_tenant` |
| anything pushed to the OTLP receiver | a `custom` destination declared by the module | propagated from the request |

**A write with no header lands in `unattributed`**, a tenant that is never one of the configured
ones and carries a short retention.

This is platform-scoped because reversing it changes the console as much as the stores: how many
datasources exist, which correlation links can be wired, and two of the console's inputs.

## Rationale

- **Tenancy here is not a security boundary and is not pretending to be.** In OSS Mimir, Loki
  and Tempo, `X-Scope-OrgID` is a routing header; nothing checks entitlement. Validating it
  would mean an authorizing proxy this lab does not have and does not want. What tenancy buys is
  per-tenant limits, per-tenant retention and reads that can be scoped, and all three are real
  on a box where disk is the binding constraint.
- **Deriving the tenant from the certificate would couple two things that should stay apart.**
  There is one shared client certificate, so the derivation would produce exactly one tenant and
  nothing would be gained. More importantly, it would make adding a tenant a certificate
  operation.
- **Stamping per ingest path was simpler and answers a different question.** It would say
  whether telemetry arrived from inside or outside the cluster, which is a fact the source
  labels already carry. The caller knows what it is; a route does not.
- **Trusting the caller is proportionate.** Inside the cluster there is one tenant and it is the
  operator. Outside, reaching the endpoint at all requires the client certificate
  ([REQ-14](../requirements.md)). A caller that lies about its tenant is one that already has
  write access and has chosen to mislabel its own telemetry.
- **`unattributed` is not a way to make the header optional.** A caller still must send one to
  control where its data lands. What it changes is the failure: without it, the collector
  answers `200` and the store rejects the write afterwards, so the data is gone and nobody is
  told. With it, the same mistake produces a visible tenant filling with orphaned telemetry —
  which names the problem and points at whoever caused it.

## Consequences

- **The collector's configuration is partly this repo's**, which
  [ADR 014](014-exposed-does-not-mean-authorized.md) declined to take on — but through a
  supported seam rather than around one. That ADR refused receiver-side *authorization* partly
  because "the collector is driven by feature flags, not by hand-authored configuration…
  inheriting every future schema change in it". The refusal stands for authorization. What is
  owned here is a handful of exporter blocks inside a first-class destination type, so what is
  inherited is Alloy's component syntax rather than the chart's generated pipeline.
- **The scrape path is unchanged.** Splitting the destinations keeps scraping and log tailing on
  their existing write paths with a static tenant, rather than converting them so that one
  destination could serve everything.
- **Every read carries a tenant.** Grafana gets one datasource per tenant per signal, and a
  correlation link only works within a tenant — a trace in one cannot open logs in another. That
  is a real reduction in what those links do, taken in exchange for the limits.
- **A tenant name is a plain string that nothing validates**, so a typo creates a tenant rather
  than an error. `unattributed` catches the empty case and nothing catches the misspelled one.
- **The limits are expressed three ways** — Mimir's runtime overrides, Loki's runtime
  `overrides`, Tempo's per-tenant override file. The one chart this repo authors is written to
  match the two it does not, so one input shape covers all three.
- **Reversible only forward.** Turning multitenancy off again makes everything written under a
  named tenant unreachable without it. This is the decision that is cheap now and expensive at
  any later date, which is most of why it is being taken now.
