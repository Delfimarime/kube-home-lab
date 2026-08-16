# LOCAL-008. A scraped workload names its own tenant, in a label

**Status:** accepted · **Scope:** module — `observability-storage-grafana-lgtm` ·
**Date:** 2026-08-16 · refines [LOCAL-001](LOCAL-001-grafana-lgtm-stack.md) and
[ADR 017](../../../adr/017-stores-are-multi-tenant.md)

## Context

[ADR 017](../../../adr/017-stores-are-multi-tenant.md) made every store multi-tenant and said the
tenant comes from the caller. The pushed path does exactly that — an `X-Scope-OrgID` on the request
is carried forward by the exporter. The scrape path could not: *"a scrape has no request behind it
to carry a header"*, so everything scraped in the cluster was written under one name,
`default_tenant`, and a workload had no way to say it belonged anywhere else.

That was the right first answer and it is the wrong second one. Per-tenant ingestion limits and
retention are the whole of what tenancy buys here
([ADR 017](../../../adr/017-stores-are-multi-tenant.md)), and a cluster running workloads for more
than one tenant cannot reach them for anything that only exposes `/metrics` — which is most things,
and everything with an upstream chart.

There is no setting that closes the gap directly. A `prometheus.remote_write` header is fixed per
endpoint: `tenantId` takes a string or a Secret reference, never a series label. Reading the tenant
off the data is not a property a write client has.

## Decision

**A workload states its tenant in a Kubernetes label, `opentelemetry.io/tenant`, and the collector
routes on it.**

Three mechanisms, and each is load-bearing:

**1. The label becomes a series label at discovery.** Two relabel rules, injected into
`prometheus.operator.servicemonitors` through `serviceMonitors.extraDiscoveryRules`, copy the
sanitised Kubernetes meta-label onto the series as `tenant`:

```alloy
rule {                                                    # the fallback
  source_labels = ["__meta_kubernetes_pod_label_opentelemetry_io_tenant"]
  regex         = "(.+)"
  target_label  = "tenant"
}
rule {                                                    # wins where it has a value
  source_labels = ["__meta_kubernetes_service_label_opentelemetry_io_tenant"]
  regex         = "(.+)"
  target_label  = "tenant"
}
```

**Pod first and Service second, because `regex = "(.+)"` writes nothing when the source is empty.**
The Service's value therefore replaces the pod's where it has one and leaves it standing where it
does not. Written the other way round the fallback would win every time both were set. A PodMonitor
has no Service to read and gets the first rule only; a Probe has neither and is not routed.

The two spellings are not interchangeable: a metric label name holds neither a dot nor a slash, so
`opentelemetry.io/tenant` is what an operator writes on a workload and `tenant` is what the router
matches.

**2. One destination per tenant, and a router in front.** The chart's `router` destination type
stamps a `selected_destinations` label from the route conditions and gates one real destination per
tenant behind it. Routes are generated from `var.tenants`, in this order:

| Series | Route | Lands in |
| --- | --- | --- |
| `tenant` names a configured tenant | `label: tenant, op: equals` | that tenant |
| `tenant` set to anything else | `label: tenant, op: matches, value: .+` | `unattributed` |
| no `tenant` label at all | `defaultDestinations` | `default_tenant` |

First declared wins, so the known tenants are claimed before the catch-all reaches them.

**3. Logs route the same way, from the pod label only.** `podLogsViaLoki.labels` maps the pod label
to the same `tenant` Loki label, and a second router with `ecosystem: loki` carries the same routes.
**There is no Service anywhere in the logs pipeline**, so a tenant written only on a Service routes
that workload's metrics and not its logs.

**What is not routed:** `clusterMetrics`, the node and state exporters, and `clusterEvents`. They
describe the cluster rather than any workload in it, so they are written as `default_tenant`
directly rather than through a router with nothing to match on.

## Rationale

- **The label is the scrape path's version of the header, not a new idea.** A push states its tenant
  per request because it has a request; a scraped workload states it once, in the only place a
  collector can see. Both end as `X-Scope-OrgID` on a write, which is why the three-way outcome
  above is the same three-way outcome the pushed path already had: your tenant, `unattributed` if
  you got it wrong, and the cluster's own if you said nothing.
- **`unattributed` for an unknown tenant is the point of it.** A label reading `tema-a` is a typo
  that nothing in the cluster can catch — the routes are the only closed list, and a value not in
  them silently joining `default_tenant` would be indistinguishable from correct configuration. It
  lands in the tenant that exists to be noticed and has the short retention to prove it.
- **Unlabelled means the cluster's own tenant, deliberately, and not `unattributed`.** An unlabelled
  workload has not forgotten anything: most of what runs here is platform infrastructure, and its
  telemetry belonged to `default_tenant` before any of this existed. Routing it anywhere else would
  make every environment's existing data move on upgrade.
- **A destination per tenant is what the header costs.** N tenants plus `unattributed` means N+1
  write clients in one `alloy-metrics`, each with its own queue and WAL, and the same again for
  logs. Fine for a handful of tenants and not for fifty — the ceiling is real and it is the reason
  the routers are generated from the tenant map rather than from anything open-ended.
- **The router is built unconditionally, including for a single-tenant environment.** One code path
  in the module, one behaviour to reason about in every environment, and the typo case is caught in
  the lab exactly as it is in a cluster with five tenants. The cost is one extra write client where
  a single-tenant environment used to have one.

## Consequences

- **The label name is a contract, and it is spelled in more than one module.** Every module that
  stamps it declares it as its own constant, because a module is applied standalone and cannot read
  a value from another one. [ADR 025](../../../adr/025-a-workload-carries-its-tenant.md) is where
  the name is agreed; this module is only one of the places it appears.
- **`tenant` stays on the stored series and stream.** It is one low-cardinality label, it is
  redundant with the org ID that already partitions the data, and dropping it would take a
  destination-level processing rule in two dialects. Kept, because it makes the routing decision
  visible in the data it applied to.
- **The destinations' names encode tenants**, as `metrics-tenant-<name>` and `logs-tenant-<name>`.
  That spelling is what keeps them from colliding with `metrics-push` and `metrics-router`, which is
  a constraint the chart's flat destination map imposes and not a naming preference.
- **`tenantId` reaches Alloy through a Secret per destination**, which is the chart's own doing —
  one more Secret per tenant per signal, holding a name that is not a credential.
- **Traces are unaffected.** They have no scrape path at all; a trace arrives pushed or not at all,
  and its tenant has always come from its own header.
