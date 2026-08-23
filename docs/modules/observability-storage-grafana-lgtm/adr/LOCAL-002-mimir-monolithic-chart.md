# LOCAL-002. Mimir runs monolithic, from a chart this repo authors

**Status:** accepted · **Scope:** module — `observability-storage-grafana-lgtm` ·
**Date:** 2026-08-12 · revised 2026-08-15 (multitenancy is on; the override surface conforms) ·
revised 2026-08-16 (blocks go to object storage)

**Mimir runs as a single process from a chart this repository authors, because no monolithic chart
exists upstream.**

## Decision

Run Mimir as a single process from a chart authored in this repository, at
`modules/observability-storage-grafana-lgtm/helm/mimir-monolithic/`:

- `-target=all` — one binary, one StatefulSet, one pod
- `common.storage.backend: s3`, one bucket, no PVC —
  [LOCAL-006](LOCAL-006-stores-keep-their-data-in-an-object-store.md)
- `-auth.multitenancy-enabled=true`, so every read and write carries `X-Scope-OrgID`
  ([ADR 017](../../../adr/017-stores-are-multi-tenant.md))
- a runtime overrides file for per-tenant limits and retention, **shaped to match Loki's and
  Tempo's** rather than expressing the same idea a third way — this is the chart this repo
  controls, so it is the one that conforms
- ruler and Alertmanager unused — nothing in this module alerts, and the console module owns
  that decision

The custom-chart case is the one
[ADR 010](../../../adr/010-resources-delivered-via-chart.md) already allows: a chart authored
here, at `helm/<chart-name>/` inside the module that owns it, because no upstream one fits.

## Context

The metrics half of [LOCAL-001](LOCAL-001-grafana-lgtm-stack.md) is the part that does not fit
a tiny cluster, and it does not fit for two independent reasons.

**There is no monolithic Helm chart for Mimir, and Grafana does not intend to write one.**
`mimir-distributed` is the only official chart and it deploys the microservices topology:
distributor, ingester, querier, query-frontend, store-gateway, compactor, plus caches and a
gateway. Ten to twelve pods before anything is scraped.

**Mimir wants object storage.** S3, GCS, Azure Blob, or an S3-compatible service, so the cost of
the metrics store includes a second storage system that exists only to serve it. This ADR
originally answered that by putting blocks on a PVC and accepting a backend Grafana documents as
unsuitable for production. That half is now decided the other way, for all three stores at once,
in [LOCAL-006](LOCAL-006-stores-keep-their-data-in-an-object-store.md) — the object store that
was rejected here as "MinIO in a distributed topology" turned out to be available as one pod on
one volume, which is a different bill from the one this paragraph was written against.

Both of these were direct hits on [REQ-10](../../../requirements.md), and between them they are
most of the reason the metrics half of
[LOCAL-001](LOCAL-001-grafana-lgtm-stack.md) is the expensive half. Only the first of them is
still unanswered, and it is what the rest of this decision is about.

Worth noting where Grafana itself landed on this: `grafana/otel-lgtm`, their own
single-container LGTM image, ships **Prometheus rather than Mimir**. The minimal build of the
stack does not use the M.

## Rationale

- One pod is the only shape of Mimir that belongs on a two-node k3s. The alternatives were
  `mimir-distributed` — ten to twelve pods, which contradicts
  [REQ-10](../../../requirements.md) outright — or substituting Prometheus,
  which is what Grafana's own minimal image does but leaves the module named for a component
  it does not run. What changed on 2026-08-16 is only the storage backend behind that one pod;
  the topology argument is untouched.
- Monolithic mode is a supported Mimir deployment mode, documented and flagged. It is not a
  hack; it is the mode without a chart.
- **Multitenancy is on, and this ADR previously said the opposite.** Turning it off does remove
  a header from every write path, every datasource and every future debugging session — which
  was the right trade for a lab with one tenant and no way to bound what an external pusher
  writes. Per-tenant limits are that bound, and switching this on later would be a data
  migration rather than a configuration change. The argument and its reversal are both in
  [ADR 017](../../../adr/017-stores-are-multi-tenant.md); revised here rather than
  superseded because nothing implements this yet.
- **Owning the chart is what makes the override surface conform.** Loki's and Tempo's per-tenant
  configuration is whatever their charts expose; this one can be written to match, so
  `var.tenants` has one shape across three stores instead of three shapes behind one input.
- The chart is small — a StatefulSet, a Service, a ConfigMap and a PVC — because everything
  that makes `mimir-distributed` large is topology this deployment does not have.

## Alternatives

- **`mimir-distributed`, the only official chart.** It deploys distributor, ingester, querier,
  query-frontend, store-gateway and compactor, plus caches and a gateway — ten to twelve pods
  before anything is scraped.
- **`mimir-distributed` with replicas forced to one.** Still every component as its own
  Deployment, still the microservices topology, now with none of the availability that shape
  exists to provide.
- **A community monolithic chart.** None found that was maintained and pinnable; authoring a small
  one here was judged cheaper than depending on one that stops being updated.
- **Prometheus instead of Mimir.** Removes the object-storage dependency and gives up the
  multitenancy [ADR 017](../../../adr/017-stores-are-multi-tenant.md) requires.

## Consequences

- **Each environment's Argo CD must have this repository registered as a source.** The
  `mimir` Application sources `repoURL` + `path` from here rather than a Helm registry. No
  other module needs this, so it joins k3s, Argo CD, the Gateway and PostgreSQL as a
  per-environment prerequisite, and it is the one a reader will not expect.
- **A chart to maintain**, against the repo's own stated preference for upstream charts with
  upstream values. The bill is real; it is small only because the topology is.
- **No horizontal scaling, by construction.** `-target=all` scales by running more whole
  Mimirs, which is not something this cluster will ever do.
- **Compactor and store-gateway still share a process**, which is what `-target=all` means. They
  no longer share a volume, so the part of that arrangement Grafana declines to support is gone
  and the part that is simply "one process doing every job" remains, which is the mode's own
  documented behaviour.
- **The chart now renders no PersistentVolumeClaim at all**, so the node pinning this decision
  used to carry moved to whatever serves the bucket. Moved, not removed — see
  [LOCAL-006](LOCAL-006-stores-keep-their-data-in-an-object-store.md).
- Reversible at a cost: moving to `mimir-distributed` later means ten more pods and a
  configuration rewrite, though no longer a storage migration — the blocks are already where
  that topology expects them. The reverse of this decision is not a values change.
