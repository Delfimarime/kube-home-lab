# 3. Standalone Grafana, and alerting inside it

**Status:** accepted · **Date:** 2026-08-05

## Context

`victoria-metrics-k8s-stack` bundles Grafana, vmalert and Alertmanager as subcharts. That
makes Grafana a child of the metrics component — so `enable_logs_support = true` with
`enable_metrics_support = false` would leave the lab with logs and no way to look at them.

Grafana's own Unified Alerting can evaluate rules against any datasource and route
notifications, which overlaps almost entirely with vmalert plus Alertmanager.

## Decision

Disable the `grafana`, `vmalert` and `alertmanager` subcharts. Deploy Grafana as its own
Argo CD Application, always enabled, with datasources generated from whichever component
flags are set. Alerting lives in Grafana.

Grafana comes from `grafana-community/helm-charts`, not `grafana/helm-charts`.

## Rationale

- Grafana spans all three components, so it cannot be gated by the metrics flag.
- Dropping vmalert and Alertmanager removes two workloads from a one-node cluster for
  capability Grafana already has.
- The `grafana/grafana` chart carries a migration notice: updates moved to
  `grafana-community/helm-charts` after 30 January 2026. Pinning the old repo means tracking
  a frozen chart.

## Consequences

- **The curated alert rules are lost.** The stack ships roughly a hundred Kubernetes alerts
  as `VMRule` CRs, which only vmalert consumes. Alerts are now hand-written in Grafana.
  Mitigating factor: a large share of those rules concern etcd quorum and control-plane
  redundancy, which do not exist on a single node.
- **Alerting stops when Grafana stops.** With vmalert the alerting path was independent of
  the UI. Accepted: one node, one human, and Grafana being down is noticeable.
- Recording rules are effectively unavailable. None are in use.
- `defaultDashboards.enabled` must be set to `true` explicitly, because it otherwise follows
  `grafana.enabled`, which is now `false`. The standalone Grafana picks the resulting
  ConfigMaps up through its dashboard sidecar.
- Reversible: re-enabling vmalert to consume `VMRule` CRs is a values change, not a redesign.
