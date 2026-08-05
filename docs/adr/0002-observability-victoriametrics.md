# 2. Observability: VictoriaMetrics family, three independent components

**Status:** accepted · **Date:** 2026-08-05

## Context

The lab needs metrics, logs and traces on one k3s node. Not all three are wanted from day
one, and whichever are enabled have to share a single query UI.

The obvious alternative is the Prometheus ecosystem: kube-prometheus-stack for metrics, Loki
for logs, Tempo for traces. Three projects, three storage engines, three operational models.

## Decision

Use the VictoriaMetrics family, one chart per component, each behind its own flag:

| Component | Chart | Flag |
| --- | --- | --- |
| metrics | `victoria-metrics-k8s-stack` | `enable_metrics_support` |
| logs | `victoria-logs-single` | `enable_logs_support` |
| traces | `victoria-traces-single` | `enable_traces_support` |

All three default to `false`. A validation requires at least one to be `true`.

## Rationale

- One vendor, one storage engine lineage — VictoriaTraces is built on VictoriaLogs, which
  shares VictoriaMetrics' design. One mental model instead of three.
- Materially cheaper on a small node. Upstream measures VictoriaTraces at roughly 3.7× less
  RAM and 2.6× less CPU than Grafana Tempo.
- No object storage or external database required for any of the three.
- Standalone charts for logs and traces (rather than the operator's `VLSingle`/`VTSingle`
  CRDs) keep the flags genuinely independent — `traces` without `metrics` does not drag in
  the operator.

## Consequences

- Three chart versions to track instead of one bundle.
- Default retention is 7 days across the family. Adequate here; disk is the scarce resource.
- Traces are queried through VictoriaTraces' Jaeger-compatible API, so Grafana uses a Jaeger
  datasource rather than a native one.
- Logs need the `victoriametrics-logs-datasource` plugin installed in Grafana.
- Fewer community tutorials than the Prometheus ecosystem. Expect to read upstream docs.
