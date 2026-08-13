# LOCAL-002. Mimir runs monolithic, from a chart this repo authors

**Status:** accepted · **Scope:** module — `observability-grafana-lgtm` ·
**Date:** 2026-08-12

## Context

The metrics half of [LOCAL-001](LOCAL-001-grafana-lgtm-stack.md) is the part that does not fit
a tiny cluster, and it does not fit for two independent reasons.

**There is no monolithic Helm chart for Mimir, and Grafana does not intend to write one.**
`mimir-distributed` is the only official chart and it deploys the microservices topology:
distributor, ingester, querier, query-frontend, store-gateway, compactor, plus caches and a
gateway. Ten to twelve pods before anything is scraped.

**Mimir wants object storage.** S3, GCS, Azure Blob, or an S3-compatible service — which in a
homelab means running MinIO, so the cost of the metrics store includes a second storage system
that exists only to serve it.

Both of these are direct hits on [REQ-10](../../../requirements.md), and between them they are
most of the reason the metrics half of
[LOCAL-001](LOCAL-001-grafana-lgtm-stack.md) is the expensive half.

Worth noting where Grafana itself landed on this: `grafana/otel-lgtm`, their own
single-container LGTM image, ships **Prometheus rather than Mimir**. The minimal build of the
stack does not use the M.

## Decision

Run Mimir as a single process from a chart authored in this repository, at
`modules/observability-grafana-lgtm/helm/mimir-monolithic/`:

- `-target=all` — one binary, one StatefulSet, one pod
- `common.storage.backend: filesystem`, one PVC, no object store and no MinIO
- `-auth.multitenancy-enabled=false`, so nothing anywhere carries `X-Scope-OrgID`
- ruler and Alertmanager unused, per [LOCAL-004](LOCAL-004-no-alerting.md)

The custom-chart case is the one
[ADR 010](../../../adr/010-resources-delivered-via-chart.md) already allows, and
`dependencies/postgresql/helm/` is the existing precedent for this repo authoring a chart
because no upstream one fits.

## Rationale

- One pod and no object store is the only shape of Mimir that belongs on a two-node k3s. The
  alternatives were `mimir-distributed` plus MinIO — which contradicts
  [REQ-10](../../../requirements.md) outright — or substituting Prometheus,
  which is what Grafana's own minimal image does but leaves the module named for a component
  it does not run.
- Monolithic mode is a supported Mimir deployment mode, documented and flagged. It is not a
  hack; it is the mode without a chart.
- Turning multitenancy off removes a header from every write path, every datasource and every
  future debugging session, for a lab with one tenant.
- The chart is small — a StatefulSet, a Service, a ConfigMap and a PVC — because everything
  that makes `mimir-distributed` large is topology this deployment does not have.

## Consequences

- **Each environment's Argo CD must have this repository registered as a source.** The
  `mimir` Application sources `repoURL` + `path` from here rather than a Helm registry. No
  other module needs this, so it joins k3s, Argo CD, the Gateway and PostgreSQL as a
  per-environment prerequisite, and it is the one a reader will not expect.
- **A chart to maintain**, against the repo's own stated preference for upstream charts with
  upstream values. The bill is real; it is small only because the topology is.
- **The filesystem blocks backend is documented as not recommended for production.** Compactor
  and store-gateway run in the same process and share the volume. This is untested here across
  restarts, and it is an open item on the spec rather than a settled question.
- **No horizontal scaling, by construction.** `-target=all` scales by running more whole
  Mimirs, which is not something this cluster will ever do.
- **The PVC is node-pinned** on k3s `local-path`. A reschedule to the other node loses the
  metrics. That is true of Loki, Tempo and Grafana here too, and it is not solved anywhere in
  this repo.
- Reversible at a cost: moving to `mimir-distributed` later means an object store, ten more
  pods and a data migration. The reverse of this decision is not a values change.
