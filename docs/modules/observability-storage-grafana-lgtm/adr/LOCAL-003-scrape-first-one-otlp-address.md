# LOCAL-003. Scrape first; publish one neutral address for what cannot be scraped

**Status:** accepted · **Scope:** module — `observability-storage-grafana-lgtm` ·
**Date:** 2026-08-12 ·
revised 2026-08-16 (the features follow a component's presence, not a flag —
[LOCAL-007](LOCAL-007-a-signal-is-its-own-configuration.md))

## Context

Nothing in the Grafana stack collects anything. Mimir, Loki and Tempo all wait to be written
to, so something has to scrape, tail and receive. Three questions came with that.

**What collects?** Grafana's `k8s-monitoring` chart is the supported path: Alloy, plus
`kube-state-metrics`, `node-exporter` and Kubernetes scrape presets, with destinations pointed
at Mimir, Loki and Tempo. Its reputation on a small cluster is that it deploys Alloy five ways
— `alloy-metrics`, `alloy-logs`, `alloy-singleton`, `alloy-receiver`, `alloy-profiles` — which
on two nodes reads as too much machinery for a lab that may not even want logs. That objection
suggested splitting the collector by flag: `k8s-monitoring` only alongside Loki, and some
lighter standalone agent when only metrics are on.

**Push or pull?** [ADR 004](../../../adr/004-scrape-config-via-prometheus-crds.md) already made
scraping the platform's mechanism for metrics: every workload declares itself through its own
chart's `serviceMonitor.enabled`, and no scrape resource is written by hand. Meanwhile the
Grafana stack's own idiom is OTLP push, and an earlier draft of this ADR led with it — which
would have quietly demoted a platform-wide decision to a per-module preference.

**What address do consumers get?** The obvious answer is one endpoint per backend — a
remote-write URL, a log push URL, an OTLP URL — so a workload addresses a store directly. It is
also how a consumer's configuration ends up naming the implementation, and how it ends up
re-wired every time a signal is toggled.

## Decision

**Scraping is the default path.** Metrics are pulled, via `ServiceMonitor` and `PodMonitor`
discovery, exactly as ADR 004 requires. Logs are tailed from the node filesystem. Only traces
are pushed, because only traces cannot be anything else.

**One collector.** `k8s-monitoring` is deployed unconditionally, and its *features* follow which
components the module ships. No new input, and no dependency between the components.

| Shipped | Features | Collectors it creates |
| --- | --- | --- |
| `components.metrics` | `clusterMetrics`, `prometheusOperatorObjects` | `alloy-metrics` |
| `components.logs` | `podLogsViaLoki`, `clusterEvents` | `alloy-logs` (DaemonSet), `alloy-singleton` |
| *always* | `applicationObservability` | `alloy-receiver` |

`annotationAutodiscovery` stays off. The module also ships `prometheus-operator-crds` as its
own Application, present when metrics are and sync-waved ahead of the collector.

**One address, named for a protocol.** The receiver Service is renamed to `otlp` through
`alloy-receiver.fullnameOverride`, and the module publishes a single
`otlp_endpoint = otlp.<namespace>.svc.cluster.local:4317`. No per-backend endpoint is
published.

## Rationale

- **Scraping costs a consumer nothing, and that is the argument.** `serviceMonitor.enabled:
  true` and the collector comes and finds you — no address, no output, no configuration to
  drift. Two of the three signals arrive this way. Leading with OTLP would have inverted the
  default for a stack idiom, against a platform decision that predates this module.
- **[ADR 004](../../../adr/004-scrape-config-via-prometheus-crds.md) survives with one fewer
  moving part.** Alloy consumes `ServiceMonitor` and `PodMonitor` directly, so the *conversion
  layer* ADR 004 allows for — a collector that speaks its own scrape dialect — is not needed
  here at all. A platform decision that gets simpler under a different implementation is the
  strongest available evidence it was made at the right altitude.
- **The five-collector figure is the all-features default, not a floor.** Which collectors
  exist is derived from which features are on. Metrics-only is `alloy-metrics` plus
  `alloy-receiver` — two pods, which is what any standalone agent would have cost. The
  objection was right about the default and wrong about the floor.
- **A second collector could not have been cheaper anyway.** `ServiceMonitor` discovery is not
  a property of an agent; it is a property of a controller watching those CRDs, and the
  lightweight agents that would have been worth swapping in do not do it. Using one here would
  mean either hand-written scrape configuration — which kills
  [ADR 004](../../../adr/004-scrape-config-via-prometheus-crds.md) for this module and silently
  breaks every other module's `serviceMonitor.enabled` — or installing that agent's own
  operator alongside it, which is strictly heavier than the single Alloy pod it was meant to
  save.
- **One discovery mechanism, not two.** `annotationAutodiscovery` would add
  `prometheus.io/scrape` alongside the CRDs, so a target could be declared in two places,
  scraped twice, and authoritative in neither. ADR 004 already chose.
- **`otlp` names a protocol; `alloy-receiver` names a product.** The output *name* was already
  neutral, but its *value* would have read
  `k8s-monitoring-alloy-receiver.observability.svc.cluster.local` — pasted into workloads and
  then unchangeable. [REQ-09](../../../requirements.md) applied to the value, not just the key.
- **Per-signal names were rejected as unimplementable.** `traces.`, `logs.` and `metrics.`
  would resolve to the same socket on the same pod: OTLP carries all three over one listener,
  and the signal is selected by gRPC method or HTTP path by the caller. Three names would
  encode a distinction that lives one layer down, and the first person to assume `logs.`
  behaves differently would be reasonable and wrong.

## Consequences

- **The CRDs are now this module's job, explicitly.** `k8s-monitoring` no longer bundles the
  Prometheus operator CRDs; Grafana's own documentation says to install them first. So the
  module ships `prometheus-operator-crds` at sync-wave 0, with `ServerSideApply=true` — those
  CRDs exceed the 262144-byte `last-applied-configuration` annotation limit, and without it the
  first sync fails in a way that does not name the cause. ADR 004 assigned this job to the
  observability module; here it is a visible Application rather than a side effect of another
  chart, which is an improvement.
- **Alloy is on the data path for traces, not only the scrape path.** If it is down, spans
  stop. Metrics and logs stop too, but they would have anyway — there is no direct-push
  workload to keep working. On a cluster with one operator that is noticeable rather than
  silent, which is the only reason it is acceptable.
- **A workload that cannot speak OTLP and exposes no `/metrics` has no route in.** No
  per-backend endpoint is published. Adding one later is an output, not a redesign, but it is
  deliberately absent rather than forgotten.
- **Port 4318 exists and is not published.** OTLP/HTTP is on the same Service for anything that
  cannot do gRPC; the spec documents it rather than publishing a second output for the same
  host.
- **`k8s-monitoring`'s values are not a stable surface.** The pod-logs feature has already
  split into three and `onlyGatherNewLogLines` has already flipped its default. Pin the chart
  and read the changelog before bumping.
- **DaemonSets cost one pod per node.** Enabling logs on two nodes costs three pods, not one.
- `kube-state-metrics` and `node-exporter` follow the metrics flag rather than arriving as a
  side effect of the metrics chart, so they are unaffected if the metrics store is swapped
  again.
