# Module: observability-storage-grafana-lgtm

**Status:** draft ·
**Satisfies:** [REQ-02, REQ-06, REQ-09, REQ-10](../../requirements.md) ·
**Decisions:** [LOCAL-001](adr/LOCAL-001-grafana-lgtm-stack.md),
[LOCAL-002](adr/LOCAL-002-mimir-monolithic-chart.md),
[LOCAL-003](adr/LOCAL-003-scrape-first-one-otlp-address.md),
[LOCAL-004](adr/LOCAL-004-storage-split-from-console.md),
[ADR 004](../../adr/004-scrape-config-via-prometheus-crds.md),
[ADR 005](../../adr/005-modules-are-applicationsets.md),
[ADR 007](../../adr/007-modules-receive-credentials.md),
[ADR 010](../../adr/010-resources-delivered-via-chart.md),
[ADR 014](../../adr/014-exposed-does-not-mean-authorized.md)

## Intent

Collect whichever of metrics, logs and traces the environment wants, and store them — each of
the three independently switchable and none of them required, using the Grafana stack so that
the correlation between them is the product's own feature rather than something assembled here
([LOCAL-001](adr/LOCAL-001-grafana-lgtm-stack.md)).

**This module is the write path and the stores. It is not the way you look at them.** Reading
belongs to [`observability-console-grafana`](../observability-console-grafana/README.md), which
was split out of what used to be one module
([LOCAL-004](adr/LOCAL-004-storage-split-from-console.md)). Grafana is the console because
these stores are Grafana's, and that pairing is the whole reason the stack was chosen — but
Grafana needs PostgreSQL, an issuer and a person, and none of those are needed to *ingest* a
span. The split is that sentence made structural.

Scoped to one environment, like every module: each cluster that ships it gets its own stores
([ADR 011](../../adr/011-environments-are-clusters.md)). There is no cross-environment view, by
design.

## Provisions

One Argo CD `ApplicationSet` ([ADR 005](../../adr/005-modules-are-applicationsets.md)), whose
`List` generator produces five Applications, of which **one** is unconditional:

| Wave | Application | Chart | Condition |
| --- | --- | --- | --- |
| 0 | `prometheus-operator-crds` | `prometheus-operator-crds` (prometheus-community) | `enable_metrics_support` |
| 1 | `mimir` | `mimir-monolithic` — authored by this repo | `enable_metrics_support` |
| 1 | `loki` | `loki`, `deploymentMode: SingleBinary` | `enable_logs_support` |
| 1 | `tempo` | `tempo` — the monolithic chart, not `tempo-distributed` | `enable_traces_support` |
| 2 | `k8s-monitoring` | `k8s-monitoring-routed` — authored here, wrapping `k8s-monitoring` | always |

**The waves are load-bearing.** A `List` generator has no inherent order, so the Applications
carry `argocd.argoproj.io/sync-wave` annotations. The CRDs must exist before `k8s-monitoring`
syncs, or Alloy's generated configuration references API types the cluster does not have. The
CRD Application also sets `ServerSideApply=true`: the Prometheus operator CRDs exceed the
262144-byte `last-applied-configuration` annotation limit, and without it the first sync fails
with an error that does not obviously say so.

**The collector is unconditional, and gating it would break the others.** Nothing reaches *any*
store without it, so tying it to one signal's flag would silently disable the rest. Which
*collectors* it creates does follow the flags — see below.

**Mimir** runs as a single process, `-target=all`, on a filesystem blocks backend and with
multitenancy off. There is no upstream monolithic chart and Grafana does not intend to write
one, which is why this module ships its own
([LOCAL-002](adr/LOCAL-002-mimir-monolithic-chart.md)).

**Loki** and **Tempo** both have real single-binary charts on local filesystem storage — one
pod each, no object store. Loki's `gateway`, `chunksCache` and `resultsCache` are switched
off; they are the chart's defaults and pure overhead at this size.

**`k8s-monitoring-routed` is this repo's first wrapped chart** — the case
[ADR 010](../../adr/010-resources-delivered-via-chart.md) defined and until now nothing needed.
`k8s-monitoring` renders no Gateway API resource for its receiver, so a chart local to this
module declares it as a Helm dependency and adds one `templates/httproute.yaml` on top. Nothing
else is re-authored, and the upstream values dialect is unchanged.

### How telemetry arrives

**Scraping is the default path, and it is the one that costs a workload nothing**
([ADR 004](../../adr/004-scrape-config-via-prometheus-crds.md),
[LOCAL-003](adr/LOCAL-003-scrape-first-one-otlp-address.md)). The three signals do not arrive
the same way, and only one of them needs an address:

| Signal | How it arrives | What the workload configures |
| --- | --- | --- |
| **metrics** | **scraped** — Alloy discovers `ServiceMonitor`/`PodMonitor`, pulls `/metrics`, remote-writes to Mimir | `serviceMonitor.enabled: true`, and nothing else |
| **logs** | **tailed** — `alloy-logs` reads container stdout from the node filesystem | nothing at all |
| **traces** | **pushed** — OTLP to the receiver | the endpoint |

Traces are the exception because there is no alternative: a span cannot be scraped, it exists
only when the application emits it. So `otlp_endpoint` serves traces, plus the case of an
application instrumented with an OTel SDK that exposes no `/metrics` at all.

`annotationAutodiscovery` is **off**. It is a second discovery mechanism —
`prometheus.io/scrape` annotations — and ADR 004 already picked one. Running both means a
target can be declared in two places, scraped twice, and authoritative in neither. Workloads
with no chart of their own still get a hand-written `ServiceMonitor` from the module that owns
them, exactly as ADR 004 anticipated.

**The collector scales with the flags.** `k8s-monitoring` is feature-gated, and which Alloy
collectors exist is derived from which features are on. This is what keeps the module
proportionate on a two-node cluster ([REQ-10](../../requirements.md)):

| Flag | Feature enabled | Collector | Pods on two nodes |
| --- | --- | --- | --- |
| `enable_metrics_support` | `clusterMetrics`, `prometheusOperatorObjects` | `alloy-metrics` | 1 |
| `enable_logs_support` | `podLogsViaLoki`, `clusterEvents` | `alloy-logs` (DaemonSet), `alloy-singleton` | 3 |
| *(none — always)* | `applicationObservability` | `alloy-receiver` | 1 |

`alloy-receiver` is unconditional because OTLP carries all three signals over one listener.
Gating it on `enable_traces_support` would leave `otlp_endpoint` with nothing to point at on a
metrics-only environment.

`kube-state-metrics` and `node-exporter` arrive with `clusterMetrics`, so they follow the
metrics flag rather than being a side effect of whichever store was chosen.

**The receiver Service is named `otlp`**, via `alloy-receiver.fullnameOverride` — a values
line, not an extra object. The in-cluster endpoint is therefore
`otlp.<namespace>.svc.cluster.local:4317` and names a protocol rather than a product. One
listener serves everything: **4317** is OTLP/gRPC, **4318** is OTLP/HTTP, and on both the
signal is selected by the caller — by gRPC method, or by path (`/v1/traces`, `/v1/metrics`,
`/v1/logs`).

### Exposure

**Route.** Wrapped case per [ADR 010](../../adr/010-resources-delivered-via-chart.md): the local
chart renders one `HTTPRoute` from `var.gateway`, addressing port **4318**, with one rule per
enabled signal:

| Rule | Exists when | Backend |
| --- | --- | --- |
| `PathPrefix: /v1/metrics` | `enable_metrics_support` | `otlp:4318` |
| `PathPrefix: /v1/logs` | `enable_logs_support` | `otlp:4318` |
| `PathPrefix: /v1/traces` | `enable_traces_support` | `otlp:4318` |

**OTLP/HTTP, not gRPC.** Routing 4317 would need an `h2c` backend protocol on the Service and a
`GRPCRoute` rather than an `HTTPRoute` — two implementation-specific behaviours to depend on,
for a transport advantage that means nothing to a laptop pushing spans over a home network.
4317 remains the in-cluster address, where neither problem exists.

**Paths, and this is not a reversal of [LOCAL-003](adr/LOCAL-003-scrape-first-one-otlp-address.md).**
That ADR refused three DNS names because they would resolve to one socket on one pod and encode
a distinction living a layer down. `/v1/traces` is where the OTLP/HTTP specification itself puts
the distinction, so the route surface matches the flags exactly, and pushing a signal this
environment does not store gets a `404` rather than a silent drop.

**No store is ever routed.** Mimir, Loki and Tempo are reachable only from inside the cluster,
whatever `gateway` is set to.

**Nothing authorizes the endpoint** ([ADR 014](../../adr/014-exposed-does-not-mean-authorized.md)).
Anything that resolves the hostname can write into the stores, and multitenancy is off, so all
of it lands in one tenant. The surface is write-only — OTLP accepts telemetry and returns
nothing, so there is no read path through it — and that, rather than the size of the cluster,
is what makes the posture defensible. Adding authorization at the listener costs this module
nothing: `gateway.section_name` already names it.

### What the console reads

The module publishes an address per store it actually runs, and
[`observability-console-grafana`](../observability-console-grafana/README.md) builds a
datasource from each. Which correlation links Grafana gets is derived there, from which of the
three addresses is non-null.

One half of that wiring lives here, because it is a store's own configuration rather than a
datasource's: **Tempo's `metrics-generator` is enabled only when metrics and traces are both
on**, remote-writing `traces_service_graph_request_total` and its siblings into Mimir. With
metrics off it stays disabled, so the console has no Service Graph tab offering a query nothing
can answer. That is a genuine dent in [REQ-02](../../requirements.md) — the signals stay
independent, but the best feature spans two of them — and it is recorded rather than discovered.

## Inputs

```hcl
enable_metrics_support = false   # at least one of the three must be true
enable_logs_support    = false
enable_traces_support  = false

gateway = null   # exposes the OTLP receiver; no store is ever routed

storage_node_selector = null   # e.g. { "kubernetes.io/hostname" = "k3s-01" }
```

Plus a namespace, chart versions, and a per-component values override.

**`gateway` is the only shared contract this module takes**, unchanged in shape
([ADR 007](../../adr/007-modules-receive-credentials.md)). `database` and `oidc` left with
Grafana: nothing here has state worth a database, a user to authenticate, or a permission to
decide. That is the clearest evidence the split was drawn in the right place.

Note that `gateway` here exposes an ingest endpoint rather than a UI, which is the first time
that contract has been used for something a person does not look at. Its shape and meaning are
unchanged — *emit a route for this workload* — and what happens to a request once it arrives is
[ADR 014](../../adr/014-exposed-does-not-mean-authorized.md)'s subject, not this input's.

**`storage_node_selector` applies to Mimir, Loki and Tempo only** — the three components that
own a volume. It must never reach `alloy-logs` or `node-exporter`: those are DaemonSets, and
running on every node is the whole point of them. `nodeSelector` rather than `affinity`, because
`kubernetes.io/hostname` is a built-in label on every node, so naming a specific machine needs
no labelling step and no set expression. Where one component needs a different node than the
others, the per-component values override is the escape hatch; that case does not deserve its
own input.

## Outputs

| Output | Used by |
| --- | --- |
| `otlp_endpoint` | in-cluster workloads exporting traces, and OTel-SDK workloads with no `/metrics` |
| `otlp_url` | the same, from outside the cluster — `null` unless `gateway` is set |
| `metrics_url` | the console, as a datasource — `null` unless metrics are on |
| `logs_url` | the console, as a datasource — `null` unless logs are on |
| `traces_url` | the console, as a datasource — `null` unless traces are on |
| `metrics_enabled` | consumers deciding whether to declare scraping |

**The three store addresses are the console's whole input, and they are nullable on purpose.**
Handing the console three booleans instead would let "metrics are on" and "there is a Mimir to
point at" disagree; an address that is either a URL or `null` cannot. No output, and no output's
*value*, names a product.

## Acceptance criteria

Scenario IDs are not reused, so the numbering has gaps: the scenarios that moved to the console
module took new `CON-` IDs and left their `OBS-` numbers behind, and the three that asserted
something about both halves at once were retired rather than split.

```gherkin
Feature: Telemetry is collected and stored, independently per signal

  @plan
  Scenario: [OBS-01] At least one component is required
    Given all three enable flags are false
    When terraform plan runs
    Then it fails with a validation error naming the three flags

  @cluster
  Scenario: [OBS-06] Scraping needs no address and no conversion
    Given enable_metrics_support is true
     And a workload's chart sets serviceMonitor.enabled to true
    When that chart is applied
    Then Alloy discovers the ServiceMonitor directly, with no conversion step
     And the target's series arrive in Mimir
     And the workload was given no endpoint of any kind

  @plan
  Scenario: [OBS-08] The published address names no product
    Given any combination of enable flags
    When otlp_endpoint is read
    Then it addresses a Service named otlp

  @cluster
  Scenario: [OBS-09] The collector costs only what is switched on
    Given only enable_metrics_support is true
    When Alloy workloads in the namespace are listed
    Then alloy-metrics and alloy-receiver exist
     And no alloy-logs DaemonSet and no alloy-singleton exist

  @cluster
  Scenario: [OBS-11] Storage placement is chosen, and DaemonSets are exempt
    Given storage_node_selector names a node
    When the module is applied
    Then every Mimir, Loki and Tempo pod runs on that node
     And alloy-logs and node-exporter still run on every node

  @cluster
  Scenario: [OBS-15] One address ingests every signal that cannot be scraped
    Given all three enable flags are true
     And a workload configured only with otlp_endpoint
    When it exports traces, metrics and logs over OTLP
    Then each arrives in Tempo, Mimir and Loki respectively

  @cluster
  Scenario: [OBS-16] The service graph is populated by real traffic
    Given the module is applied with metrics and traces enabled
     And a workload exporting spans to otlp_endpoint has served requests
    When Mimir is queried for traces_service_graph_request_total
    Then a series exists naming that workload

  @cluster
  Scenario: [OBS-17] Only the switched-on stores exist
    Given only enable_logs_support is true
    When Applications in the namespace are listed
    Then a loki Application exists
     And no mimir Application and no tempo Application exist

  @cluster
  Scenario: [OBS-18] No store is ever reachable from outside
    Given a gateway is supplied
    When HTTPRoutes in the namespace are listed
    Then none of them addresses Mimir, Loki or Tempo

  @cluster
  Scenario Outline: [OBS-19] Each switched-on signal gets an external path, and no other
    Given a gateway is supplied
     And only <flag> is true
    When <path> is requested through the Gateway
    Then the result is <outcome>

    Examples:
      | flag                   | path         | outcome                  |
      | enable_metrics_support | /v1/metrics  | accepted by the receiver |
      | enable_metrics_support | /v1/traces   | 404, with no route       |
      | enable_traces_support  | /v1/traces   | accepted by the receiver |
      | enable_traces_support  | /v1/logs     | 404, with no route       |

  @cluster
  Scenario: [OBS-20] Nothing is exposed without a gateway
    Given gateway is null
    When HTTPRoutes in the namespace are listed
    Then none exist
     And otlp_url is null

  @cluster
  Scenario: [OBS-21] Ingest is unauthenticated, and write-only
    Given a gateway is supplied and enable_traces_support is true
    When a span is pushed to /v1/traces carrying no credential of any kind
    Then it is accepted and arrives in Tempo
     And no request to that host returns any stored telemetry

  @cluster
  Scenario: [OBS-22] The generator follows both of its ends
    Given enable_traces_support is true and enable_metrics_support is false
    When Tempo's configuration is read
    Then its metrics-generator is disabled
     And nothing is remote-writing to a Mimir that does not exist
```

## Open items

- **Nothing bounds what an external pusher can write.**
  [ADR 014](../../adr/014-exposed-does-not-mean-authorized.md) accepts an unauthenticated
  endpoint on the grounds that the failure is a full volume rather than a leak — but nothing
  here caps the volume. A rate limit or a body-size limit is the cheapest thing that turns an
  accident into a nuisance, and it needs the same `ExtensionRef` filter that authorization
  would.
- **In-cluster and external ingest disagree about a switched-off signal.** Externally a
  disabled signal has no route and returns `404`. In-cluster the receiver accepts it and the
  data goes nowhere, because `alloy-receiver` is unconditional. The external behaviour is the
  better one; the asymmetry is a consequence of where the gate can be placed, not a choice.
- **Flipping a flag off is destructive, and nothing warns you.** Setting
  `enable_logs_support = false` removes the Application, and with pruning enabled the PVC goes
  with it. The flags are this module's headline feature, which makes this the sharpest edge on
  the page. Decide whether the PVCs carry a retain annotation before anyone flips one in anger.
- **Two local charts now, and Argo CD must be able to read this repository.** `mimir-monolithic`
  and `k8s-monitoring-routed` are both sourced from here rather than an upstream Helm registry.
  That joins k3s, Argo CD and the Gateway as a per-environment prerequisite.
- **The wrapper pins two versions.** `k8s-monitoring-routed` carries its own version *and* the
  upstream dependency's. A bump is two edits, and forgetting the second is a change that looks
  applied and is not.
- **Tempo's metrics-generator is the most expensive optional thing in the module**, because it
  processes every span to produce the service graph — and the service graph is most of why this
  stack was chosen. Measure it before assuming it fits on two nodes.
- **Local-path PVCs pin a pod to a node, permanently.** `volumeBindingMode:
  WaitForFirstConsumer` binds the volume to whichever node the pod first landed on, and the
  scheduler will not move it afterwards. The failure mode is not lost data — it is a pod stuck
  `Pending` once that machine is gone. `storage_node_selector` makes the choice deliberate;
  nothing here makes it recoverable.
- **Confirm Mimir's filesystem blocks backend across a restart.** Compactor and store-gateway
  are in `-target=all` and share one volume. Grafana documents the filesystem backend as not
  for production. The ruler is also in `-target=all` and unused — give `ruler_storage` a
  benign setting rather than leaving the component to find out.
- **Loki deletes nothing without its compactor.** `limits_config.retention_period` is a
  declaration; `compactor.retention_enabled` is what enforces it. Easy to set, and easy to
  believe you already did.
- **Retention is expressed three different ways** — Mimir's `compactor.blocks-retention-period`,
  Loki's `limits_config.retention_period`, Tempo's `compaction.block_retention`. Seven days
  each. Set a size cap too; disk is the limit, and it is a different limit in each environment.
- **Pin `k8s-monitoring` and read its changelog before bumping.** The pod-logs feature has
  already split into three (`podLogsViaLoki`, `podLogsViaOpenTelemetry`,
  `podLogsViaKubernetesAPI`) and `onlyGatherNewLogLines` has already flipped its default. Its
  values are not a stable surface.
- **Two nodes means DaemonSets cost two.** `alloy-logs` and `node-exporter` are per-node. The
  pod budget is `n + 2`, not `n`.
