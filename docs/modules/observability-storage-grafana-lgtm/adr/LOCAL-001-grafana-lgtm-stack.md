# LOCAL-001. Observability: the Grafana stack, three single-binary components

**Status:** accepted · **Scope:** module — `observability-storage-grafana-lgtm` ·
**Date:** 2026-08-12 · revised 2026-08-16 (the stores keep their data in an object store)

## Context

[REQ-02](../../../requirements.md) requires metrics, logs and traces to be independently
present or absent, [REQ-03](../../../requirements.md) requires whichever are on to share one
query surface, and [REQ-10](../../../requirements.md) caps all of it at what a tiny k3s cluster
can carry, per environment.

Three signals in one place is the easy half. The hard half is what happens *between* them. A
trace is only useful if you can reach the logs of the span that failed; a suspicious point on a
graph is only useful if you can open the request that produced it; and a service graph — what
calls what, and how often it fails — is not a property of any one signal at all. Every
observability stack can store three signals. They differ in whether the links between them are
a product feature or an integration project.

The Grafana stack's links are a product feature. Tempo's metrics-generator derives service-graph
series from spans; Grafana's Loki, Tempo and Prometheus-compatible datasources reference each
other by UID, so trace-to-logs, logs-to-trace and exemplars are datasource configuration rather
than code. Grafana is also where the three would be read regardless, so nothing is being adopted
merely to make the links work.

What it costs is memory, and memory is the budget [REQ-10](../../../requirements.md) actually
constrains — spent all day, every day, and now spent once per environment
([ADR 011](../../../adr/011-environments-are-clusters.md)).

## Decision

Use the Grafana stack, one chart per component, each behind its own flag:

| Component | Chart | Flag |
| --- | --- | --- |
| metrics | `mimir-monolithic` — authored here, see [LOCAL-002](LOCAL-002-mimir-monolithic-chart.md) | `enable_metrics_support` |
| logs | `loki`, `deploymentMode: SingleBinary` | `enable_logs_support` |
| traces | `tempo` — the monolithic chart, not `tempo-distributed` | `enable_traces_support` |

All three default to `false`. A validation requires at least one to be `true`. Grafana and the
collector are deployed unconditionally, because each spans all three signals and so cannot be
gated by any one flag.

Every component runs as a single process. No operator and no distributed topology anywhere in
the module — where the bytes land is [LOCAL-006](LOCAL-006-stores-keep-their-data-in-an-object-store.md)'s
subject, and it does not change the topology chosen here.

## Rationale

- **Correlation is the purchase.** Exemplars, trace-to-logs, logs-to-trace and the service
  graph are four features that exist in the product and cost datasource configuration rather
  than integration work.
- **Native datasources.** Loki and Tempo are first-class in Grafana — no plugin to install, and
  no trace store addressed through a compatibility API pretending to be something it is not.
- **Single-binary charts exist for logs and traces**, so the flags stay genuinely independent:
  `traces` without `metrics` drags in nothing extra. That property is
  what [REQ-02](../../../requirements.md) is actually asking for, and it is the reason the
  monolithic `tempo` chart is used rather than `tempo-distributed`.
- **Grafana's own state goes to PostgreSQL, and `database` is required** — the standard contract
  ([ADR 007](../../../adr/007-modules-receive-credentials.md)), and every environment is already
  assumed to have a reachable PostgreSQL, so this is an existing contract being used rather than
  a new dependency. Datasources and dashboards are provisioned from values and regenerate from
  git; users, preferences and annotations do not. Allowing the chart's SQLite default would put
  the only irreplaceable state in the module onto the node-pinned volume that is its weakest
  point, so the fallback is removed rather than merely discouraged. It also leaves Grafana owning
  no volume at all.

## Consequences

- **This is the memory-expensive way to satisfy REQ-02 and REQ-03, and it is paid per
  environment.** Lighter stacks exist and would leave more headroom on the same hardware. The
  correlation between signals is what is being bought with that headroom; an environment that
  would rather have the RAM should ship a different implementation of the capability, which is
  what [REQ-09](../../../requirements.md) exists to permit.
- **The service graph needs metrics and traces both on.** The signals stay independently
  switchable, but the headline feature spans two of them, so REQ-02's independence is now "each
  is optional" rather than "each is complete alone". Asserted by OBS-07.
- **Metrics costs a chart this repo maintains** — see
  [LOCAL-002](LOCAL-002-mimir-monolithic-chart.md), which is the contested half of this decision
  and has its own ADR for that reason.
- **Grafana now needs PostgreSQL to start.** It is the module's only hard external dependency,
  and one the platform's assumptions already require of every environment.
- **No default dashboards.** Nothing in this stack ships a Kubernetes dashboard set. Import by
  `gnetId` or start blank.
- Five chart versions to track — three components, the collector and Grafana — plus the
  Prometheus operator CRD bundle.
- **Retention defaults to seven days per component**, expressed differently by each of the
  three. Disk is the scarce resource, and it is a different amount of disk in each environment.
