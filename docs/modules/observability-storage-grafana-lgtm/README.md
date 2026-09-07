# Module: observability-storage-grafana-lgtm

**Status:** implemented ·
**Satisfies:** [REQ-02, REQ-06, REQ-09, REQ-10](../../requirements.md) ·
**Decisions:** [LOCAL-001](adr/LOCAL-001-grafana-lgtm-stack.md),
[LOCAL-002](adr/LOCAL-002-mimir-monolithic-chart.md),
[LOCAL-003](adr/LOCAL-003-scrape-first-one-otlp-address.md),
[LOCAL-004](adr/LOCAL-004-storage-split-from-console.md),
[LOCAL-006](adr/LOCAL-006-stores-keep-their-data-in-an-object-store.md),
[LOCAL-007](adr/LOCAL-007-a-signal-is-its-own-configuration.md),
[LOCAL-008](adr/LOCAL-008-a-scraped-workload-names-its-own-tenant.md),
[ADR 004](../../adr/004-scrape-config-via-prometheus-crds.md),
[ADR 005](../../adr/005-modules-are-applicationsets.md),
[ADR 007](../../adr/007-modules-receive-credentials.md),
[ADR 010](../../adr/010-resources-delivered-via-chart.md),
[ADR 014](../../adr/014-exposed-does-not-mean-authorized.md),
[ADR 020](../../adr/020-one-root-module.md),
[ADR 016](../../adr/016-metrics-is-the-fourth-input.md),
[ADR 017](../../adr/017-stores-are-multi-tenant.md),
[ADR 022](../../adr/022-secrets-are-rendered-empty.md),
[ADR 025](../../adr/025-a-workload-carries-its-tenant.md),
[ADR 027](../../adr/027-charts-are-first-class-artifacts.md)

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
`List` generator produces up to eight Applications, of which **one** is unconditional:

| Wave | Application | Chart | Condition |
| --- | --- | --- | --- |
| 0 | `<name>` | `secret-template` — imported, see [ADR 022](../../adr/022-secrets-are-rendered-empty.md) | one per distinct storage credential this module renders — see below |
| 0 | `prometheus-operator-crds` | `prometheus-operator-crds` (prometheus-community) | `components.metrics` is set |
| 1 | `mimir` | `mimir-monolithic` — authored by this repo | `components.metrics` is set |
| 1 | `loki` | `loki`, `deploymentMode: SingleBinary` | `components.logs` is set |
| 1 | `tempo` | `tempo` — the monolithic chart, not `tempo-distributed` | `components.traces` is set |
| 2 | `k8s-monitoring` | `k8s-monitoring-routed` — authored here, wrapping `k8s-monitoring` | always |

**Charts this repository publishes are at `helm/<chart>/`, not in this module's directory** — here
[`helm/mimir-monolithic`](../../../helm/mimir-monolithic) and
[`helm/k8s-monitoring-routed`](../../../helm/k8s-monitoring-routed), both at version `0.1.0`. A
module renders against a chart's published values schema, and the chart's `Chart.yaml` version is
what moves when that schema does, so **it may have consumers other than this one**. Check before
editing it.

**A component's presence is what ships it** ([LOCAL-007](adr/LOCAL-007-a-signal-is-its-own-configuration.md)).
There is no `enable_metrics_support` and no sibling of it: the block that says where metrics land
and how long they are kept is the same block whose absence means they are not collected. At
least one must be present.

**There can be more than one credential Application, and usually there is one.** Wave 0 renders
a placeholder per *distinct* Secret name this module is asked to create — the top-level
`object_storage` with `secret_name` null gives `<namespace>-object-storage-credentials`, and a
component carrying its own block with `secret_name` null gives
`<namespace>-<signal>-object-storage-credentials`. Names that coincide produce one Application, and
naming existing Secrets throughout produces none.

**The namespace is in those names because the Application's name is the Secret's**
([ADR 022](../../adr/022-secrets-are-rendered-empty.md)). Applications all live in the Argo CD
namespace while Secrets live in their own, so an unqualified `object-storage-credentials` here is the
same Application as the one [`object-storage-silo`](../object-storage-silo/README.md) renders for
its own copy of this credential — and the second ApplicationSet to reach it is refused with
`already owned by another ApplicationSet controller`.

**The waves are load-bearing.** A `List` generator has no inherent order, so the Applications
carry `argocd.argoproj.io/sync-wave` annotations. The CRDs must exist before `k8s-monitoring`
syncs, or Alloy's generated configuration references API types the cluster does not have. The
CRD Application also sets `ServerSideApply=true`: the Prometheus operator CRDs exceed the
262144-byte `last-applied-configuration` annotation limit, and without it the first sync fails
with an error that does not obviously say so.

**The collector is unconditional, and gating it would break the others.** Nothing reaches *any*
store without it, so tying it to one signal would silently disable the rest. Which *collectors*
it creates does follow the components — see below.

**Mimir** runs as a single process, `-target=all`, with multitenancy on
([ADR 017](../../adr/017-stores-are-multi-tenant.md)). There is no
upstream monolithic chart and Grafana does not intend to write one, which is why this module
ships its own ([LOCAL-002](adr/LOCAL-002-mimir-monolithic-chart.md)) — and because it is this
repo's chart rather than somebody else's, its per-tenant override surface is shaped to match
Loki's and Tempo's rather than being a third dialect.

**Loki** and **Tempo** both have real single-binary charts — one pod each. Loki's `gateway`,
`chunksCache` and `resultsCache` are switched off; they are the chart's defaults and pure
overhead at this size.

**All three stores declare their own scraping**, through their chart's `serviceMonitor` switch like
every other workload here, whenever this module ships a metrics store. Loki's chart also rewrites the
`cluster` label to its release name unless told otherwise, so `clusterLabelOverride` is set to
`cluster_name` — without it this store's series would be the one place `cluster` names something
other than the cluster.

**No store owns a volume.** All three write their blocks, chunks and traces to buckets in the
environment's object store ([LOCAL-006](adr/LOCAL-006-stores-keep-their-data-in-an-object-store.md)),
which is what their vendors support and what the earlier filesystem backends were not. The
endpoint arrives as `var.object_storage` and is required; there is no filesystem fallback,
because a fallback is what you get by forgetting an input and this one would be the unsupported
configuration.

**Each store names its own bucket, and no store can be told to share one**
([LOCAL-007](adr/LOCAL-007-a-signal-is-its-own-configuration.md)). `bucket` lives in the
component and has no counterpart in `object_storage`, at either level, so there is no global
default to inherit and nothing to forget. Two components naming the same bucket is refused at
plan time.

**A store may also be pointed at a different endpoint entirely**, by carrying its own
`object_storage`. That block replaces the top-level one outright rather than merging into it —
see [Inputs](#inputs), where the cost of that choice is stated, because it is the one place in
this module where a plain-looking configuration can be wrong.

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

**The collector scales with the components.** Which Alloy collectors exist is derived from which
features are on. This is what keeps the module proportionate on a two-node cluster
([REQ-10](../../requirements.md)):

| Shipped | Feature enabled | Collector | Pods on two nodes |
| --- | --- | --- | --- |
| `components.metrics` | `clusterMetrics`, `prometheusOperatorObjects` | `alloy-metrics` | 1 |
| `components.logs` | `podLogsViaLoki`, `clusterEvents` | `alloy-logs` (DaemonSet), `alloy-singleton` | 3 |
| *(none — always)* | `applicationObservability` | `alloy-receiver` | 1 |

`alloy-receiver` is unconditional because OTLP carries all three signals over one listener.
Gating it on `components.traces` would leave `otlp_endpoint` with nothing to point at on a
metrics-only environment.

`kube-state-metrics` and `node-exporter` arrive with `clusterMetrics`, so they follow the
metrics component rather than being a side effect of whichever store was chosen.

**At the pinned version the collectors are declared, not inferred.** `k8s-monitoring` 4.4.0 takes
`collectors` as an explicit map and `destinations` as a map keyed by name; earlier versions
derived the collector set from the features alone. The table above still describes what ends up
running — this module now says so directly rather than letting the chart work it out, which is
one more place a version bump can change the meaning of unchanged values.

**The receiver Service is named `otlp`**, via `collectors.alloy-receiver.fullnameOverride` — a
values line, not an extra object. The in-cluster endpoint is therefore
`otlp.<namespace>.svc.cluster.local:4317` and names a protocol rather than a product. One
listener serves everything: **4317** is OTLP/gRPC, **4318** is OTLP/HTTP, and on both the
signal is selected by the caller — by gRPC method, or by path (`/v1/traces`, `/v1/metrics`,
`/v1/logs`).

### Tenancy

**All three stores run multi-tenant, and the tenant comes from the caller**
([ADR 017](../../adr/017-stores-are-multi-tenant.md)). `X-Scope-OrgID` is mandatory
on every read and write — `multitenancy_enabled` in Mimir and Tempo, `auth_enabled` in Loki,
which enables *tenancy* and not authentication despite its name.

**Nothing validates the header.** A caller states its tenant and is believed. This is not
isolation and is not meant to be: what it buys is per-tenant ingestion limits, per-tenant
retention, and reads that can be scoped. The limits are the part that matters here — they are
what bounds an external pusher, which
[ADR 014](../../adr/014-exposed-does-not-mean-authorized.md) accepted having no answer for.

**The collector propagates a header where a request exists and routes on a label where one does
not.** The chart's destinations split in three, and each feature selects the ones it belongs to:

| Path | Destination | Tenant |
| --- | --- | --- |
| operator objects — `ServiceMonitor`, `PodMonitor` — and tailed pod logs | `router`, fanning out to one `prometheus` / `loki` destination per tenant | from the workload's `opentelemetry.io/tenant` label |
| cluster metrics, the exporters, cluster events | `prometheus` / `loki` for `default_tenant` | static: they describe the cluster, not a workload |
| anything pushed to the receiver | `custom`, `ecosystem: otlp` | propagated from the request |

**This module's own workloads are collected as `telemetry-storage`**, a tenant it stamps on the
three stores itself and that `var.tenants` refuses a caller for — the same standing as
`unattributed`. Both are published as `reserved_tenants` so the console builds a datasource for
each. It holds each store's own `/metrics` and container logs; kube-state-metrics' and the node
exporter's view of the same pods is cluster-wide and stays with `default_tenant`, so a storage
health dashboard spans two datasources.

**A scraped workload names its own tenant in a label**
([LOCAL-008](adr/LOCAL-008-a-scraped-workload-names-its-own-tenant.md)): two relabel rules copy
`opentelemetry.io/tenant` off the Service, or off the pod where the Service does not carry it, onto
the series as `tenant`; one router per label-based pipeline matches it against the tenants in
`var.tenants` and writes through that tenant's own client. A label naming a tenant this environment
does not have lands in `unattributed`; no label at all lands in `default_tenant`. Logs are discovered
from pods and see no Service at all, so a tenant written only on a Service routes metrics and not
logs.

The cost is one write client per tenant per signal, each with its own queue and WAL, in the one
`alloy-metrics` and the one `alloy-logs`.

The pushed side declares one `otelcol.exporter.otlphttp` per store, each carrying an
`otelcol.auth.headers` handler that reads `X-Scope-OrgID` from the incoming request and re-emits
it — so a workload's choice survives the hop. The receiver is told to keep request metadata
through `applicationObservability.receivers.otlp.{grpc,http}.includeMetadata`.

The scrape path reaches the same place from the other end: no request exists to carry a header, so
the tenant comes off the workload as a label and the router chooses which `prometheus.remote_write`
or `loki.write` client — and therefore which fixed `X-Scope-OrgID` — the write goes through
([ADR 017](../../adr/017-stores-are-multi-tenant.md),
[LOCAL-008](adr/LOCAL-008-a-scraped-workload-names-its-own-tenant.md)).

**A write with no header — or a scrape whose label names a tenant that does not exist — lands in
`unattributed`.** That tenant is never one of the configured ones and carries a short retention. It exists because the alternative is worse: Alloy answers
`200` and the store rejects the write afterwards, so a forgotten header silently loses data.
An `unattributed` tenant filling up says who forgot.

**Getting that fallback takes two blocks, because Alloy has no `default_value`.** The upstream
`headerssetter` extension has one; Alloy's `otelcol.auth.headers` wrapper exposes `key`,
`action`, `value`, `from_context` and `from_attribute` and nothing else, so the obvious
one-block version cannot be written. Two blocks, **in this order**, reconstruct it exactly:

```alloy
otelcol.auth.headers "tenant" {
  header {
    key          = "X-Scope-OrgID"
    action       = "upsert"
    from_context = "X-Scope-OrgID"
  }
  header {
    key    = "X-Scope-OrgID"
    action = "insert"
    value  = "unattributed"
  }
}
```

A missing metadata key yields the empty string rather than an error, `upsert` writes it anyway,
and `insert` treats an empty header as absent — so the second block fills in only when the first
found nothing. **Order is load-bearing and the reverse silently overwrites a real tenant with
nothing.** It also only works over HTTP: on gRPC the two actions operate on a map, where `insert`
tests for *presence* rather than emptiness, sees the empty value the first block wrote, and skips.
The exporters are `otelcol.exporter.otlphttp`, so this module is on the path where it works —
which is now a reason not to switch them, and not merely the choice
[Exposure](#exposure) made for the route.

| Signal | Limits under `var.tenants` | Applied by |
| --- | --- | --- |
| metrics | ingestion rate, series, retention | Mimir runtime overrides |
| logs | ingestion rate, stream limits, retention | Loki runtime `overrides` |
| traces | ingestion rate, retention | Tempo per-tenant overrides |

### Retention

**Three levels, and only the top one is this module's invention.** Every store already has a
global limit and a per-tenant override above it; the third level exists so an environment writes
its number once rather than three times
([LOCAL-007](adr/LOCAL-007-a-signal-is-its-own-configuration.md)).

| Level | Set in | Lands in |
| --- | --- | --- |
| cross-signal default | `retention.default` | nothing directly — it is what a component inherits |
| per store | `components.<signal>.retention` | Mimir `compactor_blocks_retention_period`, Loki `limits_config.retention_period`, Tempo `compaction.block_retention` |
| per tenant | `tenants.<t>.<signal>.limits.retention` | each store's per-tenant overrides |

A tenant the map does not name gets its store's own limit, which is the component's value rather
than an unbounded default — the gap that used to exist underneath `var.tenants` is now a number
somebody chose.

**`unattributed` is the exception, and it needs its own number.** It is the tenant a forgotten
header lands in, so it exists to be noticed and emptied rather than kept; inheriting a component's
retention would let telemetry nobody claimed occupy the same disk for the same week as telemetry
somebody did. It takes `retention.unattributed`, short by default, and it is the one tenant this
module writes an override for without being asked.

**Loki deletes nothing without its compactor**, whichever level set the number.
`limits_config.retention_period` is a declaration and `compactor.retention_enabled` is what
enforces it, so the module sets both and two of these three levels would otherwise be decorative.

### Exposure

**Route.** Wrapped case per [ADR 010](../../adr/010-resources-delivered-via-chart.md): the local
chart renders one `HTTPRoute` from `var.gateway`, addressing port **4318**, with one rule per
enabled signal:

| Rule | Exists when | Backend |
| --- | --- | --- |
| `PathPrefix: /v1/metrics` | `components.metrics` is set | `otlp:4318` |
| `PathPrefix: /v1/logs` | `components.logs` is set | `otlp:4318` |
| `PathPrefix: /v1/traces` | `components.traces` is set | `otlp:4318` |

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

**Authorization is the listener's, and `gateway.section_name` is how this module asks for it**
([ADR 014](../../adr/014-exposed-does-not-mean-authorized.md)). Pointing it at an mTLS listener
means only a caller holding the environment's client certificate
([certificate-management-cert-manager](../certificate-management-cert-manager/README.md)) can
reach the receiver at all. Pointing it at the ordinary TLS listener means anything that resolves
the hostname can write. **Both remain valid**, and no module change distinguishes them — which
is exactly what ADR 014 said the reversal would cost.

The posture that does not depend on which listener is chosen: **the surface is write-only**.
OTLP accepts telemetry and returns nothing, no store is ever routed, and there is no read path
through this host. That, rather than the size of the cluster, is what made the unauthenticated
case defensible and what still bounds the authenticated one.

**A client certificate says nothing about a tenant.** It admits the caller; `X-Scope-OrgID`
decides where the write lands, and the two are deliberately unrelated
([ADR 017](../../adr/017-stores-are-multi-tenant.md)).

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

## Prerequisites

**An S3-compatible endpoint, and one bucket per component shipped.** Which module provides the
endpoint is the root's business — [`object-storage-silo`](../object-storage-silo/README.md)
is the one that does today — and the buckets are created by hand there, per environment, because
nothing creates them. A bucket that is missing is not a sync failure: the store starts healthy
and the error appears on the first write. A component pointed at its own endpoint needs a bucket
*there*, and that endpoint may be nothing this repository deploys at all.

**The access key, filled in, in this module's namespace.** A Secret is namespaced, so the object
store's own copy is not readable from here — the credential has to exist a second time. With
`secret_name` left null this module renders its own placeholder, empty and with both keys
present, and its contents are ignored on every sync
([ADR 022](../../adr/022-secrets-are-rendered-empty.md)); naming an existing Secret instead means
this module only reads it. Either way what an environment owes is the value:

```sh
kubectl patch secret telemetry-object-storage-credentials -n telemetry \
  --type merge -p "$(jq -n --arg a "$(printf %s "$ACCESS_KEY" | base64)" \
                          --arg s "$(printf %s "$SECRET_KEY" | base64)" \
                          '{data:{ACCESS_KEY:$a,SECRET_KEY:$s}}')"

kubectl rollout restart statefulset/mimir statefulset/loki statefulset/tempo -n observability
```

The key names are `object_storage.access_key_key` and `secret_key_key`, which default to what
the object store module publishes; patch whatever those are set to.

**Once per credential, not once per module.** A component carrying its own `object_storage` gets
its own Secret, so an environment where one store writes elsewhere owes two values rather than
one, and the second one is not the same value.

**It must be the same value the object store was given**, and nothing checks that it is. Two
copies of one credential, filled in by hand, drifting independently: that is what having no
secret manager costs ([platform scope](../../platform.md#scope)), and the symptom of getting it
wrong is every write returning `403` while all three stores look healthy.

## Inputs

```hcl
object_storage = {               # required — the default every store inherits whole
  endpoint       = "s3-svc.object-storage.svc.cluster.local:9000"
  region         = "af-south-1"
  secret_name    = null                   # null: rendered here, in *this* namespace
                                          # set:  an existing Secret, only read
  access_key_key = "ACCESS_KEY"
  secret_key_key = "SECRET_KEY"
  insecure       = true                   # the endpoint carries no scheme; this picks one
}                                         # there is no `buckets` key, at either level

retention = {                    # the defaults every component inherits
  default      = "168h"
  unattributed = "24h"           # the tenant a forgotten header lands in
}

components = {                   # at least one; presence is what ships the store
  metrics = {
    bucket    = "mimir"                   # required; no default, and no global equivalent
    retention = "720h"                    # optional → retention.default
  }
  logs = {
    bucket = "loki"
  }
  traces = {
    bucket = "tempo"
    object_storage = {                    # optional; replaces the block above outright
      endpoint       = "s3.remote.example:9000"
      region         = "eu-west-1"
      secret_name    = "tempo-remote-credentials"
      access_key_key = "AWS_ACCESS_KEY_ID"
      secret_key_key = "AWS_SECRET_ACCESS_KEY"
    }
  }
}

gateway = null   # exposes the OTLP receiver; no store is ever routed

tenants = {                      # at least one; limits and retention per signal
  lab = {
    metrics = { limits = { ingestion_rate = 25000, retention = "168h" } }
    logs    = { limits = { ingestion_rate_mb = 4, retention = "168h" } }
    traces  = { limits = { retention = "168h" } }
  }
}

default_tenant = "lab"           # what the cluster's own collection is written as, and what an
                                 # unlabelled workload's telemetry falls back to

cluster_name = "lab"             # required; every series and every log line is labelled with it
```

Plus a namespace, chart versions, and a per-component values override.

**`cluster_name` is required and has no default.** `k8s-monitoring` refuses to render without it,
and rightly: it labels every series and every log line the collector produces, so a wrong value is
not a failure but a mislabelling that survives in the data long after it is corrected. Deriving
one from the namespace or the environment would be inventing an identity for telemetry that
outlives this cluster.

**A component is its own configuration, and its presence is the switch**
([LOCAL-007](adr/LOCAL-007-a-signal-is-its-own-configuration.md)). Where a signal lands, how long
it is kept, and whether it is collected at all are one input rather than four, and the pair that
could disagree — a flag set true while the bucket it needs is unnamed — is not expressible. At
least one component must be present; that is the only validation the three booleans used to
carry.

**`bucket` is required and has no global equivalent.** It is a field of the component, not of
`object_storage`, so there is nowhere to state one bucket for every store. No two components may
name the same bucket, and a component pointed at its own endpoint may reuse a name in use at the
default one — they are different buckets.

**`gateway` is the only shared contract this module takes**, unchanged in shape
([ADR 007](../../adr/007-modules-receive-credentials.md)). `database` and `oidc` left with
Grafana: nothing here has state worth a database, a user to authenticate, or a permission to
decide. That is the clearest evidence the split was drawn in the right place.

Note that `gateway` here exposes an ingest endpoint rather than a UI, which is the first time
that contract has been used for something a person does not look at. Its shape and meaning are
unchanged — *emit a route for this workload* — and what happens to a request once it arrives is
[ADR 014](../../adr/014-exposed-does-not-mean-authorized.md)'s subject, not this input's.
`gateway.section_name` is the whole of how this module asks for mTLS.

**`tenants` names tenants and bounds them; it does not create or restrict them.** Any caller may
write to any name it likes, including one absent from this map, and such a write lands under its
store's own limits rather than being refused
([ADR 017](../../adr/017-stores-are-multi-tenant.md)). What the map is for is limits
and retention — a tenant listed here has its own ceiling, and disk is the thing this module runs
out of first. `unattributed` is reserved and must not appear in it.

**`retention` is a pair of defaults and never a ceiling.** `retention.default` is what a
component inherits when it says nothing, and a component's value is in turn what a tenant inherits when `var.tenants` says
nothing — three levels, of which the lower two are the ones every store already has. See
[Retention](#retention) for where each lands. Nothing here bounds *size*; disk is what this
module runs out of first and retention is only one of the two things that decide when.

**`default_tenant` is not a fallback for callers.** It is what the cluster's own collection
carries — cluster metrics, the exporters, cluster events — and where a scraped workload's telemetry
lands when the workload names no tenant at all
([LOCAL-008](adr/LOCAL-008-a-scraped-workload-names-its-own-tenant.md)). A push that omits the header
gets `unattributed`, and so does a workload whose label names a tenant not in `tenants`; both are a
different thing on purpose — one is telemetry nobody had to label, the other is telemetry somebody
labelled wrong.

**`object_storage` is required and is not one of the shared contracts.** It carries an address, a
region, and a Secret name plus the two keys inside it — the credential by reference, never by
value ([ADR 007](../../adr/007-modules-receive-credentials.md)). It is an ordinary input wired at
the root like any other ([ADR 020](../../adr/020-one-root-module.md)); a fourth contract gets
added when a second module needs one, not in anticipation of it.

**A component's own `object_storage` replaces this one; it does not merge into it.** The same
object type in both positions, with the same field-level defaults, and when a component sets one
the top-level block is not consulted at all. `endpoint` is required inside an override.

**`insecure` exists because an endpoint is `host:port` and carries no scheme.** It defaults to
`true`, which is right for the endpoint this platform actually ships — a Service inside the
cluster, on plain HTTP, on a network that never leaves it. A store pointed somewhere else has to
say `insecure = false`, so the surprising case is the one that states itself. The default is
uniform across both positions rather than flipping for overrides, because a field that means two
things depending on where it is written is worse than a default that has to be overridden.

**This is the sharp edge, and it is here rather than in a footnote.** A component that overrides
only its endpoint does *not* inherit the region or the credential above it — it gets the
field-level defaults, so `region = "af-south-1"` at the top yields `us-east-1` below, silently.
The symptom is `SignatureDoesNotMatch` on first write, which names neither a region nor an
input. Replacement was chosen over merging anyway, because the alternative failure is worse and
quieter: a partial override reads as "like the others, but over there", and inheriting *this*
cluster's access key while writing to somebody else's endpoint plans clean and `403`s forever.
A component that writes elsewhere states everything about writing elsewhere.

**Only a shipped component's bucket is read**, because a bucket is only nameable inside one. An
environment shipping one signal creates one bucket, and nothing validates that it exists — see
[Prerequisites](#prerequisites).

**There is no `storage_node_selector` any more.** It placed the three components that owned a
volume, and none of them owns one now. Placing the machine that holds the data is the object
store module's input, where the volume actually is.

**Each store's version is pinned separately**, and these are the only places those versions are
written — a value set at the root would not add a second opinion, it would replace this one
silently. `loki.chart_version` and `tempo.chart_version` pin upstream charts. **Mimir's is
`mimir.image_tag` and not a chart version**, because the chart is this repository's own and its
`version` describes the packaging rather than the server; what decides which Mimir runs is the
image. Set one only to make *this* cluster run something other than what this module installs.

Plus three more inputs no environment normally writes: `prometheus_operator_crds.chart_version`,
the CRD bundle the collector reads scrape configuration from; `argocd.namespace`, where the
`ApplicationSet` object goes; and `git_repository` — this repository and the revision Argo CD
reads its charts at, which every module rendering one of them takes. This module renders two, so
it is always consulted.

## Outputs

| Output | Used by |
| --- | --- |
| `otlp_endpoint` | in-cluster workloads exporting traces, and OTel-SDK workloads with no `/metrics` |
| `otlp_url` | the same, from outside the cluster — `null` unless `gateway` is set |
| `metrics_url` | the console, as a datasource — `null` unless metrics are on |
| `logs_url` | the console, as a datasource — `null` unless logs are on |
| `traces_url` | the console, as a datasource — `null` unless traces are on |
| `object_storage_secret_names` | the operator, to know what to fill in — one entry per shipped signal |
| `reserved_tenants` | the console, to build a datasource for each tenant this module writes itself |

**The Secret names are a map rather than a name**, because a component may write somewhere else
and take its own credential with it. One string could describe three stores only while they
shared one; it cannot now, and a map that usually holds the same value three times is honest
where a single name would be a guess.

**There is no `metrics.enabled` output.** Whether an environment scrapes is decided by whether it
ships a metrics store, which this module reads as `components.metrics` and every other module is
told as `metrics.enabled` — derived once in the root module, not declared anywhere
([ADR 024](../../adr/024-the-metrics-fact-is-derived.md),
[ADR 016](../../adr/016-metrics-is-the-fourth-input.md),
[ADR 020](../../adr/020-one-root-module.md)). The derivation belongs to the root because it is the
root that knows which other modules exist; publishing it here would invite a consumer to read it
out of this module, which is the wrong direction.

**The three store addresses are the console's whole input, and they are nullable on purpose.**
Handing the console three booleans instead would let "metrics are on" and "there is a Mimir to
point at" disagree; an address that is either a URL or `null` cannot. No output, and no output's
*value*, names a product.

## Acceptance criteria

Scenario IDs are not reused, so the numbering has gaps: the scenarios that moved to the console
module took new `CON-` IDs and left their `OBS-` numbers behind, and the three that asserted
something about both halves at once were retired rather than split. `OBS-11` is retired too — it
asserted that `storage_node_selector` placed the three components owning a volume, and none of
them owns one any more. `OBS-01` is retired as of
[LOCAL-007](adr/LOCAL-007-a-signal-is-its-own-configuration.md): it asserted that all three
`enable_*_support` flags being false fails and names them, and no such input exists. Every other
scenario below asserts exactly what it always did and only states its *given* differently, so
those keep their numbers.

```gherkin
Feature: Telemetry is collected and stored, independently per signal

  @plan
  Scenario: [OBS-30] At least one component is required
    Given components is empty
    When tofu plan runs
    Then it fails with a validation error naming components

  @plan
  Scenario: [OBS-31] A shipped signal names its own bucket, and only its own
    Given components.metrics is set with no bucket
    When tofu plan runs
    Then it fails, naming the component and bucket
     And no input at any level sets a bucket for every store at once

  @plan
  Scenario: [OBS-32] Two stores may not share a bucket
    Given components.logs and components.traces name the same bucket
     And both resolve to the same endpoint
    When tofu plan runs
    Then it fails, naming both components and the bucket

  @plan
  Scenario: [OBS-33] A component's storage block replaces the default outright
    Given object_storage sets region to af-south-1
     And components.traces.object_storage sets only endpoint
    When Tempo's rendered configuration is read
    Then its region is the field default and not af-south-1
     And its credential is not the one the top-level block names

  @plan
  Scenario: [OBS-34] An override must say where it writes
    Given components.traces.object_storage is set with no endpoint
    When tofu plan runs
    Then it fails, naming the component and endpoint

  @plan
  Scenario Outline: [OBS-35] Retention falls through three levels
    Given retention is 168h
     And components.logs.retention is <component>
     And tenants.lab.logs.limits.retention is <tenant>
    When Loki's rendered configuration is read
    Then limits_config.retention_period is <effective>
     And the lab override is <override>

    Examples:
      | component | tenant | effective | override |
      | unset     | unset  | 168h      | absent   |
      | 72h       | unset  | 72h       | absent   |
      | 72h       | 24h    | 72h       | 24h      |

  @cluster
  Scenario: [OBS-36] Declared retention is enforced, not merely stated
    Given components.logs is set with any retention
    When Loki's rendered configuration is read
    Then compactor.retention_enabled is true

  @cluster
  Scenario: [OBS-37] One credential per distinct Secret name, and no more
    Given object_storage.secret_name is null
     And components.traces.object_storage.secret_name is null
    When Applications in the namespace are listed
    Then two secret-template Applications exist
     And they render <namespace>-object-storage-credentials and <namespace>-traces-object-storage-credentials
     And every other component reads the first of them

  @cluster
  Scenario: [OBS-06] Scraping needs no address and no conversion
    Given components.metrics is set
     And a workload's chart sets serviceMonitor.enabled to true
    When that chart is applied
    Then Alloy discovers the ServiceMonitor directly, with no conversion step
     And the target's series arrive in Mimir
     And the workload was given no endpoint of any kind

  @plan
  Scenario: [OBS-08] The published address names no product
    Given any combination of components
    When otlp_endpoint is read
    Then it addresses a Service named otlp

  @cluster
  Scenario: [OBS-09] The collector costs only what is switched on
    Given only components.metrics is set
    When Alloy workloads in the namespace are listed
    Then alloy-metrics and alloy-receiver exist
     And no alloy-logs DaemonSet and no alloy-singleton exist

  @cluster
  Scenario: [OBS-27] No store owns a volume
    Given all three components are set
    When PersistentVolumeClaims in the namespace are listed
    Then none belongs to Mimir, Loki or Tempo
     And each store's data is in its own bucket

  @cluster
  Scenario: [OBS-28] The object store credential is never rendered
    Given object_storage names the Secret this module renders
    When each Application spec is read from the API server
    Then no access key or secret key appears in any rendered Helm values
     And each store reads them from the named Secret

  @cluster
  Scenario: [OBS-29] Only a switched-on signal's bucket is read
    Given only components.logs is set
     And only the logs bucket exists
    When the module is applied and a log line is tailed
    Then it arrives in Loki
     And nothing attempted to reach the metrics or traces buckets

  @cluster
  Scenario: [OBS-15] One address ingests every signal that cannot be scraped
    Given all three components are set
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
    Given only components.logs is set
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
     And <component> is the only one set
    When <path> is requested through the Gateway
    Then the result is <outcome>

    Examples:
      | component          | path        | outcome                  |
      | components.metrics | /v1/metrics | accepted by the receiver |
      | components.metrics | /v1/traces  | 404, with no route       |
      | components.traces  | /v1/traces  | accepted by the receiver |
      | components.traces  | /v1/logs    | 404, with no route       |

  @cluster
  Scenario: [OBS-20] Nothing is exposed without a gateway
    Given gateway is null
    When HTTPRoutes in the namespace are listed
    Then none exist
     And otlp_url is null

  @cluster
  Scenario: [OBS-21] Ingest is write-only, whatever the listener demands
    Given a gateway is supplied and components.traces is set
    When any request is made to that host
    Then no stored telemetry is returned by any of them
     And no route in the namespace addresses Mimir, Loki or Tempo

  @cluster
  Scenario Outline: [OBS-23] The listener decides who may write, and nothing else does
    Given gateway.section_name names <listener>
    When a span is pushed to /v1/traces carrying <credential>
    Then it is <outcome>

    Examples:
      | listener  | credential           | outcome                        |
      | web-tls   | no credential at all | accepted and arrives in Tempo  |
      | otlp-mtls | no credential at all | refused at the TLS handshake   |
      | otlp-mtls | the client certificate | accepted and arrives in Tempo |

  @cluster
  Scenario: [OBS-24] The caller's tenant is honoured, not replaced
    Given tenants names lab and scratch
     And a workload pushing traces with X-Scope-OrgID set to scratch
    When Tempo is queried as tenant scratch
    Then the span is there
     And querying as tenant lab does not return it

  @cluster
  Scenario: [OBS-25] A write with no tenant is kept, not lost
    Given components.metrics is set
    When a metric is pushed to the receiver carrying no X-Scope-OrgID
    Then it is stored under the unattributed tenant
     And unattributed is not present in var.tenants

  @cluster
  Scenario: [OBS-26] A tenant's ceiling is its own
    Given tenants gives lab and scratch different ingestion rate limits
    When each is written to beyond its limit
    Then each is throttled at its own limit
     And neither throttling affects the other

  @cluster
  Scenario: [OBS-22] The generator follows both of its ends
    Given components.traces is set and components.metrics is not
    When Tempo's configuration is read
    Then its metrics-generator is disabled
     And nothing is remote-writing to a Mimir that does not exist
```

## Open items

- **The pushed side's exporters are this module's to maintain.** A `custom` destination renders
  its `config` verbatim, so the retry, queue, TLS and compression settings the built-in `otlp`
  destination would have provided are written here, three times, and do not follow a chart
  upgrade.
- **The tenant fallback rests on an ordering nothing enforces.** Alloy exposes no `default_value`,
  so `unattributed` is reconstructed from an `upsert` followed by an `insert` — see
  [Tenancy](#tenancy). Swapping the two blocks silently replaces every caller's tenant with
  nothing, and no schema, lint or render catches it. The real fix is upstream: ask Grafana to
  surface `default_value` and `value_file`, both of which the extension it wraps already has.
- **Alloy's wrapper is narrower than the extension underneath it, and that is invisible from the
  configuration.** Reading `otelcol.auth.headers` against the `headerssetter` documentation
  suggests options the Alloy component does not accept. Check Alloy's own reference before using
  anything the extension documents.
- **`mimir-monolithic`'s override surface has two shapes to conform to, and they disagree.**
  Loki's `runtimeConfig` is a free map rendered into a reloadable file, keyed
  `overrides.<tenant>`; Tempo's is split between `tempo.overrides` for defaults and
  `tempo.per_tenant_overrides` for the per-tenant file. Tempo's own values also warn that *all*
  values must be given in each per-tenant block, so its per-tenant entries do not inherit the
  defaults beside them. `var.tenants` has to render both dialects from one shape and produce a
  third for Mimir; whichever way that lands, one of the three will read oddly.
- **A caller can write to a tenant that has no limits.** `var.tenants` bounds the tenants it
  names; a caller inventing a name gets the store's defaults. The volume cap that
  [ADR 014](../../adr/014-exposed-does-not-mean-authorized.md) had no answer for now exists,
  and it is opt-in per tenant rather than global.
- **In-cluster and external ingest disagree about a switched-off signal.** Externally a
  disabled signal has no route and returns `404`. In-cluster the receiver accepts it and the
  data goes nowhere, because `alloy-receiver` is unconditional. The external behaviour is the
  better one; the asymmetry is a consequence of where the gate can be placed, not a choice.
- **Dropping a component no longer destroys the data, and nothing says so either.** Removing
  `components.logs` removes the Application; the bucket and everything in it stay, because
  nothing in this module owns them. Putting the block back finds the old data waiting, which is
  the good version of this surprise and is worth knowing before someone deletes a bucket by hand
  assuming otherwise. The bucket name lives only in the block that was deleted, so the way back
  is a name nobody wrote down anywhere else.
- **Two local charts now, and Argo CD must be able to read this repository.** `mimir-monolithic`
  and `k8s-monitoring-routed` are both sourced from here rather than an upstream Helm registry.
  That joins k3s, Argo CD and the Gateway as a per-environment prerequisite.
- **The wrapper pins two versions.** `k8s-monitoring-routed` carries its own version *and* the
  upstream dependency's. A bump is two edits, and forgetting the second is a change that looks
  applied and is not.
- **Tempo's metrics-generator is the most expensive optional thing in the module**, because it
  processes every span to produce the service graph — and the service graph is most of why this
  stack was chosen. Measure it before assuming it fits on two nodes.
- **This module does not start without the object store, and nothing sequences the two.** Argo CD
  may sync a store before the endpoint is serving; the crash loop resolves itself and looks
  exactly like a wrong address, which does not.
- **A missing bucket is silent until the first write.** Every store starts healthy against a
  bucket that does not exist. The error then appears here, hours later, about a resource another
  module's spec documents creating by hand.
- **The ruler is in `-target=all` and unused** — give `ruler_storage` a benign setting rather
  than leaving the component to find out. It now has a bucket to be pointed at, which makes this
  cheaper to satisfy than it was and no less necessary.
- **Retention is expressed three different ways and now settable at three levels** — Mimir's
  `compactor.blocks-retention-period`, Loki's `limits_config.retention_period`, Tempo's
  `compaction.block_retention`, each overridable per tenant, each defaulted per component, each
  defaulted again across signals. `retention.default`, `components.<signal>.retention` and
  `var.tenants` hide the three dialects behind one shape; nothing hides that three levels is one
  more place for a number to come from than anybody will remember. **Retention still bounds
  time, not size.** Set a size cap too; disk is the limit, and it is one disk per endpoint, sized
  in another module by different reasoning, with nothing comparing the two numbers.
- **A per-component endpoint is unexercised.** Every store writing to one object store is the
  configuration that gets deployed, so the override is a path nothing runs regularly — including
  its sharpest edge, a partial-looking override silently taking field defaults for region and
  credential. `OBS-33` asserts that behaviour precisely because it is the one nobody would
  predict from reading the values.
- **Nothing checks that a per-component endpoint exists**, and it may be something this
  repository does not deploy at all. A missing bucket was already silent until the first write; a
  missing endpoint now is too, once per component, and the second one is not diagnosable from
  inside this cluster.
- **The Tempo chart this module pins is deprecated by its own maintainers.** `grafana/tempo`
  1.24.4 carries `deprecated: true` in its `Chart.yaml`. It renders and runs, and the only
  replacement Grafana offers is `tempo-distributed` — the microservices topology this module
  exists to avoid. So the pin stands, and traces are the one signal whose chart has no supported
  future at this size. That is a decision to revisit with real information, not a defect to fix.
- **`helm lint` does not catch what `helm template` does.** On Helm 4.2.1 lint reported no
  failures on a values file that `helm template` then rejected outright. Every `ci/` file gets
  rendered, not merely linted, and any CI wired up later must do the same or it verifies nothing.
- **Pin `k8s-monitoring` and read its changelog before bumping.** The pod-logs feature has
  already split into three (`podLogsViaLoki`, `podLogsViaOpenTelemetry`,
  `podLogsViaKubernetesAPI`) and `onlyGatherNewLogLines` has already flipped its default. Its
  values are not a stable surface.
- **Two nodes means DaemonSets cost two.** `alloy-logs` and `node-exporter` are per-node. The
  pod budget is `n + 2`, not `n`.
