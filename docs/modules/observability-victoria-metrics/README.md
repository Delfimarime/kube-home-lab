# Module: observability-victoria-metrics

**Status:** draft ·
**Satisfies:** [REQ-02, REQ-03, REQ-10](../../requirements.md) ·
**Decisions:** [LOCAL-001](adr/LOCAL-001-victoriametrics-family.md),
[LOCAL-002](adr/LOCAL-002-alerting-in-grafana.md),
[ADR 004](../../adr/004-scrape-config-via-prometheus-crds.md),
[ADR 007](../../adr/007-modules-receive-credentials.md)

## Intent

Provide whichever of metrics, logs and traces the environment wants, behind one Grafana,
with each of the three independently switchable and none of them required.

Scoped to one environment: each cluster that ships this module gets its own components and
its own Grafana ([ADR 011](../../adr/011-environments-are-clusters.md)). There is no
cross-environment view, by design.

## Provisions

One Argo CD `ApplicationSet` ([ADR 005](../../adr/005-modules-are-applicationsets.md)), whose
`List` generator produces four Applications, of which one is unconditional:

| Application | Chart | Condition |
| --- | --- | --- |
| `victoria-metrics-k8s-stack` | `victoria-metrics-k8s-stack` | `enable_metrics_support` |
| `victoria-logs` | `victoria-logs-single` | `enable_logs_support` |
| `victoria-traces` | `victoria-traces-single` | `enable_traces_support` |
| `grafana` | `grafana` (grafana-community) | always |

The metrics chart runs with `grafana`, `vmalert` and `alertmanager` disabled and
`defaultDashboards.enabled` forced to `true`. It contributes the VictoriaMetrics operator,
VMSingle, VMAgent, kube-state-metrics, node-exporter, the preconfigured Kubernetes scrape
targets, and the dashboard ConfigMaps that Grafana's sidecar collects.

Grafana's datasources are generated from whichever flags are set: VictoriaMetrics as
default when metrics is on, VictoriaLogs when logs is on, and a Jaeger datasource pointed at
VictoriaTraces when traces is on.

**Route.** Native case per [ADR 010](../../adr/010-resources-delivered-via-chart.md): Grafana's
own chart renders the `HTTPRoute` from `route.main`, populated from `var.gateway`. The chart's
own `ingress` stays disabled so there is exactly one path in.

## Inputs

```hcl
enable_metrics_support = false   # at least one of the three must be true
enable_logs_support    = false
enable_traces_support  = false

gateway = null    # exposes Grafana only; backends are never routed
oidc    = null    # Grafana delegates authentication when set
```

Plus a namespace, chart versions, and a per-component values override.

## Outputs

| Output | Used by |
| --- | --- |
| `metrics_query_endpoint` | Grafana datasource, ad-hoc queries |
| `metrics_remote_write_endpoint` | anything pushing metrics directly |
| `logs_endpoint` | log shippers |
| `traces_otlp_endpoint` | any workload exporting OTLP traces |
| `grafana_url` | OIDC client redirect URI registration |
| `metrics_enabled` | consumers deciding whether to declare scraping |

## Acceptance criteria

```gherkin
Feature: Observability components are independently switchable

  @plan
  Scenario: [OBS-01] At least one component is required
    Given all three enable flags are false
    When terraform plan runs
    Then it fails with a validation error naming the three flags

  @cluster
  Scenario: [OBS-02] Logs alone
    Given only enable_logs_support is true
    When the module is applied
    Then a victoria-logs Application exists
     And no VictoriaMetrics operator is installed
     And Grafana has exactly one datasource, of type VictoriaLogs

  @cluster
  Scenario: [OBS-03] Metrics and traces together
    Given enable_metrics_support and enable_traces_support are true
    When the module is applied
    Then Grafana has a VictoriaMetrics datasource marked default
     And a Jaeger datasource addressing the VictoriaTraces service

  @cluster
  Scenario: [OBS-04] Grafana survives metrics being off
    Given enable_metrics_support is false
    When the module is applied
    Then the Grafana Application still exists

  @cluster
  Scenario: [OBS-05] Only Grafana is exposed
    Given a gateway is supplied
    When HTTPRoutes in the namespace are listed
    Then exactly one exists, addressing the Grafana Service

  @cluster
  Scenario: [OBS-06] Charts can declare their own scraping
    Given enable_metrics_support is true
     And a workload's chart sets serviceMonitor.enabled to true
    When that chart is applied
    Then a VMServiceScrape is produced by conversion
     And the target appears in VMAgent's active targets
```

## Open items

- Confirm `defaultDashboards.enabled` still renders dashboard ConfigMaps with the Grafana
  subchart disabled, and the label the Grafana sidecar must select on.
- Confirm `route.main`'s schema against the pinned chart version — its comment flags it BETA
  upstream — and that the chart's own `ingress` stays disabled.
- Retention defaults to 7 days per component. Set `retentionSize` too; disk is the limit, and
  it is a different limit in each environment.
