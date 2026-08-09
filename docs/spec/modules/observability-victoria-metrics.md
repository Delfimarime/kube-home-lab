# Module: observability-victoria-metrics

**Status:** draft · **Decisions:** [ADR 2](../../adr/0002-observability-victoriametrics.md),
[ADR 3](../../adr/0003-grafana-standalone-and-alerting.md),
[ADR 4](../../adr/0004-scrape-config-via-prometheus-crds.md),
[ADR 7](../../adr/0007-modules-receive-credentials.md)

## Intent

Provide whichever of metrics, logs and traces the lab wants, behind one Grafana, with each
of the three independently switchable and none of them required.

## Provisions

One Argo CD `ApplicationSet` ([ADR 5](../../adr/0005-modules-are-applicationsets.md)), whose
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

**Route.** Native case per [ADR 10](../../adr/0010-resources-delivered-via-chart.md): Grafana's
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

  Scenario: At least one component is required
    Given all three enable flags are false
    When terraform plan runs
    Then it fails with a validation error naming the three flags

  Scenario: Logs alone
    Given only enable_logs_support is true
    When the module is applied
    Then a victoria-logs Application exists
     And no VictoriaMetrics operator is installed
     And Grafana has exactly one datasource, of type VictoriaLogs

  Scenario: Metrics and traces together
    Given enable_metrics_support and enable_traces_support are true
    When the module is applied
    Then Grafana has a VictoriaMetrics datasource marked default
     And a Jaeger datasource addressing the VictoriaTraces service

  Scenario: Grafana survives metrics being off
    Given enable_metrics_support is false
    When the module is applied
    Then the Grafana Application still exists

  Scenario: Only Grafana is exposed
    Given a gateway is supplied
    When HTTPRoutes in the namespace are listed
    Then exactly one exists, addressing the Grafana Service

  Scenario: Charts can declare their own scraping
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
- Retention defaults to 7 days per component. Set `retentionSize` too; disk is the limit.
