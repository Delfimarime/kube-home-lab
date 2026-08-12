# Module: observability-grafana-lgtm

**Status:** draft ·
**Satisfies:** [REQ-01, REQ-02, REQ-03, REQ-10](../../requirements.md) ·
**Decisions:** [LOCAL-001](adr/LOCAL-001-grafana-lgtm-stack.md),
[LOCAL-002](adr/LOCAL-002-mimir-monolithic-chart.md),
[LOCAL-003](adr/LOCAL-003-scrape-first-one-otlp-address.md),
[LOCAL-004](adr/LOCAL-004-no-alerting.md),
[LOCAL-005](adr/LOCAL-005-two-grafana-roles-strict.md),
[ADR 004](../../adr/004-scrape-config-via-prometheus-crds.md),
[ADR 005](../../adr/005-modules-are-applicationsets.md),
[ADR 007](../../adr/007-modules-receive-credentials.md),
[ADR 010](../../adr/010-resources-delivered-via-chart.md)

## Intent

Provide whichever of metrics, logs and traces the environment wants, behind one Grafana, with
each of the three independently switchable and none of them required — using the Grafana
stack, so that the correlation between the three is the product's own feature rather than
something assembled here ([LOCAL-001](adr/LOCAL-001-grafana-lgtm-stack.md)).

Scoped to one environment, like every module: each cluster that ships it gets its own
components and its own Grafana ([ADR 011](../../adr/011-environments-are-clusters.md)). There
is no cross-environment view, by design.

## Provisions

One Argo CD `ApplicationSet` ([ADR 005](../../adr/005-modules-are-applicationsets.md)), whose
`List` generator produces six Applications, of which **two** are unconditional:

| Wave | Application | Chart | Condition |
| --- | --- | --- | --- |
| 0 | `prometheus-operator-crds` | `prometheus-operator-crds` (prometheus-community) | `enable_metrics_support` |
| 1 | `mimir` | `mimir-monolithic` — authored by this repo | `enable_metrics_support` |
| 1 | `loki` | `loki`, `deploymentMode: SingleBinary` | `enable_logs_support` |
| 1 | `tempo` | `tempo` — the monolithic chart, not `tempo-distributed` | `enable_traces_support` |
| 2 | `k8s-monitoring` | `k8s-monitoring` | always |
| 2 | `grafana` | `grafana` (grafana-community) | always |

**The waves are load-bearing.** A `List` generator has no inherent order, so the Applications
carry `argocd.argoproj.io/sync-wave` annotations. The CRDs must exist before `k8s-monitoring`
syncs, or Alloy's generated configuration references API types the cluster does not have. The
CRD Application also sets `ServerSideApply=true`: the Prometheus operator CRDs exceed the
262144-byte `last-applied-configuration` annotation limit, and without it the first sync fails
with an error that does not obviously say so.

**Two Applications are unconditional, and for the same reason.** Grafana spans all three
signals, so no single flag may gate it — logs switched on with metrics off must still leave
somewhere to read them ([REQ-03](../../requirements.md)). `k8s-monitoring` is the collector,
and nothing reaches *any* backend without it, so gating it on one signal's flag would silently
disable the others.

**Mimir** runs as a single process, `-target=all`, on a filesystem blocks backend and with
multitenancy off. There is no upstream monolithic chart and Grafana does not intend to write
one, which is why this module ships its own
([LOCAL-002](adr/LOCAL-002-mimir-monolithic-chart.md)).

**Loki** and **Tempo** both have real single-binary charts on local filesystem storage — one
pod each, no object store. Loki's `gateway`, `chunksCache` and `resultsCache` are switched
off; they are the chart's defaults and pure overhead at this size.

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
line, not an extra object, so [ADR 010](../../adr/010-resources-delivered-via-chart.md) is not
in play. The published endpoint is therefore `otlp.<namespace>.svc.cluster.local:4317` and
names a protocol rather than a product. One listener serves everything: **4317** is OTLP/gRPC,
**4318** is OTLP/HTTP, and on both the signal is selected by the caller — by gRPC method, or
by path (`/v1/traces`, `/v1/metrics`, `/v1/logs`). Port 4318 is not published as a second
output; it is the same host.

### Correlation

The reason for choosing this stack. Grafana's datasources are generated from whichever flags
are set, and **each link is conditional on both of its ends existing**:

| Datasource | Gains, when… | Link | Gives you |
| --- | --- | --- | --- |
| Mimir | traces on | `exemplarTraceIdDestinations` → Tempo | a point on a graph opens its trace |
| Loki | traces on | `derivedFields` → Tempo | a log line opens its trace |
| Tempo | logs on | `tracesToLogsV2` → Loki | a span opens its logs |
| Tempo | metrics on | `serviceMap.datasourceUid` → Mimir | the service graph |

**The service graph**, specifically, because it is the least obvious of the four:

1. Tempo's `metrics-generator` derives `traces_service_graph_request_total` and its siblings
   from spans as they arrive.
2. It remote-writes those series into Mimir.
3. Grafana's Tempo datasource points `serviceMap.datasourceUid` at Mimir.
4. The Service Graph tab renders from Mimir; clicking a node drills back into Tempo.

**This requires metrics and traces to both be on.** That is a genuine dent in
[REQ-02](../../requirements.md) — the signals stay independent, but the best feature spans two
of them. It is recorded here rather than discovered later, and LGTM-07 asserts that the absence
degrades cleanly instead of half-working.

### Access

**Route.** Native case per [ADR 010](../../adr/010-resources-delivered-via-chart.md): Grafana's
own chart renders the `HTTPRoute` from `route.main`, populated from `var.gateway`. The chart's
own `ingress` stays disabled so there is exactly one path in. No backend is ever routed —
Mimir, Loki, Tempo and the OTLP receiver are reachable only from inside the cluster.

**Sign-in and authorization.** When `var.oidc` is set, Grafana's `auth.generic_oauth` is
configured from it and **two roles are recognised**
([LOCAL-005](adr/LOCAL-005-two-grafana-roles-strict.md)):

| Claim value | Grafana org role | Can |
| --- | --- | --- |
| `GRAFANA_ADMIN` | `Admin` | everything within the org, including datasources and users |
| `GRAFANA_VIEWER` | `Viewer` | read dashboards and explore; change nothing |
| *neither* | — | **not sign in at all** |

They are read from `resource_access.grafana.roles`, overridable by `var.oidc.groups_claim`
when a provider emits them elsewhere. Grafana evaluates `role_attribute_path` as **JMESPath**,
not JSONPath, so the expression carries no `$.` prefix:

```ini
role_attribute_path   = contains(resource_access.grafana.roles[*], 'GRAFANA_ADMIN') && 'Admin' || contains(resource_access.grafana.roles[*], 'GRAFANA_VIEWER') && 'Viewer' || ''
role_attribute_strict = true
```

`role_attribute_strict` is what turns "no role" into a refused login rather than a silent
default. That is [REQ-06](../../requirements.md)'s posture applied to a person instead of a
port: access is an act, not the state you end up in by not being mentioned.

The module **declares** the claim it needs; whether the issuer emits it is that issuer's
business and an operational matter, per the third shared-contract rule in
[the platform spec](../../platform.md#shared-contracts). A token without the claim produces a
refused login, not a broken module.

**The local login form follows `oidc`, and can be overridden.** `allow_local_login` defaults to
`null`, which means *derive it*: the form is on when `oidc` is `null` — otherwise there would be
no way in at all — and off once an issuer is wired, so that REQ-01's "one account" is a fact
rather than a preference. Setting it to `true` alongside `oidc` keeps the form as a break-glass
route for when the issuer is down; setting it to `false` with no `oidc` locks everyone out and
is refused at plan time.

**No alerting.** No rules, no contact points, no Alertmanager — see
[LOCAL-004](adr/LOCAL-004-no-alerting.md) for what that declines and what turning it back on
costs.

## Inputs

```hcl
enable_metrics_support = false   # at least one of the three must be true
enable_logs_support    = false
enable_traces_support  = false

gateway  = null   # exposes Grafana only; backends are never routed
oidc     = null   # Grafana delegates authentication and authorization when set
database = null   # Grafana's own state; SQLite on a PVC when null

allow_local_login     = null   # null follows oidc — see below
storage_node_selector = null   # e.g. { "kubernetes.io/hostname" = "k3s-01" }
```

Plus a namespace, chart versions, and a per-component values override.

`gateway`, `oidc` and `database` are the shared contracts, unchanged in shape
([ADR 007](../../adr/007-modules-receive-credentials.md)). `oidc.groups_claim`, when set,
replaces the default claim path for role lookup.

**`allow_local_login` is the only input with a derived default**, because the safe value depends
on another input:

| `oidc` | `allow_local_login` | Grafana's login form |
| --- | --- | --- |
| `null` | `null` | **on** — it is the only way in |
| set | `null` | **off** — one account per environment, as REQ-01 asks |
| set | `true` | **on** — deliberate break-glass, kept for when the issuer is down |
| `null` | `false` | rejected at plan time: nobody could sign in |

**`storage_node_selector` applies to Mimir, Loki, Tempo and Grafana only** — the four
components that own a volume. It must never reach `alloy-logs` or `node-exporter`: those are
DaemonSets, and running on every node is the whole point of them. `nodeSelector` rather than
`affinity`, because `kubernetes.io/hostname` is a built-in label on every node, so naming a
specific machine needs no labelling step and no set expression. Where one component needs a
different node than the others, the per-component values override is the escape hatch; that
case does not deserve its own input.

## Outputs

| Output | Used by |
| --- | --- |
| `otlp_endpoint` | workloads exporting traces, and OTel-SDK workloads with no `/metrics` |
| `grafana_url` | OIDC client redirect URI registration |
| `metrics_enabled` | consumers deciding whether to declare scraping |

Three, and the point is how few: metrics and logs need **no** output, because the collector
goes and finds them. No output, and no output's *value*, names a product.

## Acceptance criteria

```gherkin
Feature: Grafana LGTM observability is independently switchable and self-correlating

  @plan
  Scenario: [LGTM-01] At least one component is required
    Given all three enable flags are false
    When terraform plan runs
    Then it fails with a validation error naming the three flags

  @cluster
  Scenario: [LGTM-02] Logs alone
    Given only enable_logs_support is true
    When the module is applied
    Then a loki Application exists
     And no mimir Application and no tempo Application exist
     And Grafana has exactly one datasource, of type loki

  @cluster
  Scenario: [LGTM-03] The service graph is wired when both ends exist
    Given enable_metrics_support and enable_traces_support are true
    When the module is applied
    Then the Tempo datasource has serviceMap.datasourceUid set to the Mimir datasource
     And Tempo's metrics-generator is enabled and remote-writing to Mimir
     And traces_service_graph_request_total is queryable in Mimir once spans have arrived

  @cluster
  Scenario: [LGTM-04] Grafana survives metrics being off
    Given enable_metrics_support is false
    When the module is applied
    Then the Grafana Application still exists

  @cluster
  Scenario: [LGTM-05] Only Grafana is exposed
    Given a gateway is supplied
    When HTTPRoutes in the namespace are listed
    Then exactly one exists, addressing the Grafana Service

  @cluster
  Scenario: [LGTM-06] Scraping needs no address and no conversion
    Given enable_metrics_support is true
     And a workload's chart sets serviceMonitor.enabled to true
    When that chart is applied
    Then Alloy discovers the ServiceMonitor directly, with no conversion step
     And the target's series arrive in Mimir
     And the workload was given no endpoint of any kind

  @cluster
  Scenario: [LGTM-07] Traces without metrics degrades cleanly
    Given enable_traces_support is true and enable_metrics_support is false
    When the Tempo datasource is read
    Then serviceMap is unset
     And Tempo's metrics-generator is disabled
     And no Service Graph tab offers a query that cannot be answered

  @cluster
  Scenario: [LGTM-08] One neutral address ingests what cannot be scraped
    Given all three enable flags are true
    When otlp_endpoint is read
    Then it addresses a Service named otlp, naming no product
    When a workload exports traces, metrics and logs to it over OTLP
    Then each arrives in Tempo, Mimir and Loki respectively

  @cluster
  Scenario: [LGTM-09] The collector costs only what is switched on
    Given only enable_metrics_support is true
    When Alloy workloads in the namespace are listed
    Then alloy-metrics and alloy-receiver exist
     And no alloy-logs DaemonSet and no alloy-singleton exist

  @cluster
  Scenario: [LGTM-10] Nothing alerts
    Given any combination of enable flags
    When the module is applied
    Then no Alertmanager is running in the namespace
     And Grafana has no provisioned alert rules and no contact points

  @cluster
  Scenario: [LGTM-11] Storage placement is chosen, and DaemonSets are exempt
    Given storage_node_selector names a node
    When the module is applied
    Then every Mimir, Loki, Tempo and Grafana pod runs on that node
     And alloy-logs and node-exporter still run on every node

  @cluster
  Scenario: [LGTM-12] Two roles, and nothing else gets in
    Given an oidc issuer is supplied
    When a person whose token carries GRAFANA_ADMIN signs in
    Then they hold the Admin org role
    When a person whose token carries GRAFANA_VIEWER signs in
    Then they hold the Viewer org role
    When a person whose token carries neither signs in
    Then the login is refused, and no account is created

  @plan
  Scenario: [LGTM-13] Local login follows oidc, and cannot lock everyone out
    Given oidc is null and allow_local_login is null
    When terraform plan runs
    Then Grafana's login form is enabled
    Given oidc is set and allow_local_login is null
    When terraform plan runs
    Then Grafana's login form is disabled
    Given oidc is null and allow_local_login is false
    When terraform plan runs
    Then it fails, naming both inputs
```

## Open items

- **Flipping a flag off is destructive, and nothing warns you.** Setting
  `enable_logs_support = false` removes the Application, and with pruning enabled the PVC goes
  with it. The flags are this module's headline feature, which makes this the sharpest edge on
  the page. Decide whether the PVCs carry a retain annotation before anyone flips one in
  anger.
- **`allow_local_login = true` is a password nobody will rotate.** The break-glass route is
  worth having when the issuer runs in this same cluster, but the account it keeps alive is a
  static credential outside the OIDC path and outside anyone's attention. If it is switched on,
  it needs an owner.
- **Tempo's metrics-generator is the most expensive optional thing in the module**, because it
  processes every span to produce the service graph — and the service graph is most of why this
  stack was chosen. Measure it before assuming it fits on two nodes.
- **Argo CD must be able to read this repository.** The `mimir` entry sources a chart from here
  rather than an upstream Helm registry. No other module needs that, so it joins k3s, Argo CD,
  the Gateway and PostgreSQL as a per-environment prerequisite
  ([LOCAL-002](adr/LOCAL-002-mimir-monolithic-chart.md)).
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
- **No dashboards ship with any of this.** Import by `gnetId` through the Grafana chart, or
  accept a blank Grafana on day one.
- **Two nodes means DaemonSets cost two.** `alloy-logs` and `node-exporter` are per-node. The
  pod budget is `n + 2`, not `n`.
