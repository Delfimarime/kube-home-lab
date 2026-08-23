# 025. A workload carries its tenant in `opentelemetry.io/tenant`

**Status:** accepted · **Scope:** platform · **Date:** 2026-08-16 ·
supersedes the one-field half of [ADR 016](016-metrics-is-the-fourth-input.md)

**A workload carries its tenant in an `opentelemetry.io/tenant` label on its Service and its pods.**

## Decision

**A workload's tenant is a Kubernetes label, `opentelemetry.io/tenant`, on its Service and on its
pods.** The collector copies it onto the series and routes the write under that tenant's
`X-Scope-OrgID`
([LOCAL-008](../modules/observability-storage-grafana-lgtm/adr/LOCAL-008-a-scraped-workload-names-its-own-tenant.md)
is how).

**`metrics` gains a second field:** `metrics = { enabled, tenant }`. A module that takes the input
writes the label from `tenant` onto every workload it deploys — the Service where its chart exposes
service labels, the pods where it exposes pod labels, and both where it exposes both.

**Both positions, because the two signals discover differently.** Metrics are discovered through the
Service a `ServiceMonitor` selects; logs are discovered from pods, and there is no Service anywhere
in that pipeline. The Service label wins for metrics where both are set; a label on only one of the
two routes only one of the two signals.

**`tenant` is null by default, and null is not "no tenant".** An unlabelled workload is collected as
the cluster's own — which is what everything this repo deploys is, unless an environment says
otherwise. The field exists for the environment that splits its platform across tenants.

**The root derives it and each unit may override it.** `metrics.enabled` comes from whether a metrics
store is shipped ([ADR 024](024-the-metrics-fact-is-derived.md)); `metrics.tenant` is the unit's own
`tenant` where one is written and `observability.default_tenant` otherwise, and the root validates it
against `observability.tenants` because that is the only place the tenant list exists.

## Context

[ADR 017](017-stores-are-multi-tenant.md) says a caller names its tenant. A workload that pushes
telemetry does so per request, in `X-Scope-OrgID`. A workload that is *scraped* has no request to put
it in, so everything collected in the cluster was stored under one name — the environment's
`default_tenant` — and a module had no way to say its workload belonged to a different tenant.

[ADR 004](004-scrape-config-via-prometheus-crds.md) rules out the obvious workaround. A module
declares scraping through its chart's `serviceMonitor.enabled` and nothing else, and a
`ServiceMonitor` has no field naming a tenant: its own metadata labels are read by whoever selects
the CR and never reach a series.

[ADR 016](016-metrics-is-the-fourth-input.md) left the room for this on purpose. It made `metrics` an
object rather than a bare boolean *"so that whatever scraping needs next — an interval, a label — has
somewhere to go without renaming the input a second time"*, while stating it carries one field.

## Rationale

- **A label is the only place a collector can look.** It is not a design preference: discovery reads
  Kubernetes objects, so a fact about a workload has to be on the workload. The alternative — a
  per-tenant collector selecting `ServiceMonitor`s by CR label — is one Alloy deployment per tenant
  for the same outcome.
- **`metrics` is where it belongs, and this is the field ADR 016 anticipated.** The tenant is not a
  contract in the [ADR 007](007-modules-receive-credentials.md) sense — it references nothing
  addressable — and it is meaningless without the collector `metrics.enabled` describes.
- **The name is not one this project owns.** `opentelemetry.io/` is a prefix OpenTelemetry defines
  labels under and has defined no tenant label in. The alternative is a prefix from this repo's own
  domain, which is more correct and reads as local convention where this reads as the ecosystem's;
  the risk is that OTel later defines the same key with a different meaning. Accepted knowingly, and
  cheap to rename — it is one constant per module and a relabel rule.
- **Validation belongs to the root and nowhere else.** A module takes a string and cannot know the
  tenant list; the storage module knows the list and never sees the workloads. Only the root sees
  both. A tenant that is not in the map does not fail anywhere downstream — the telemetry lands in
  `unattributed` — so the check has to happen at the one place it can.

## Alternatives

- **Put the tenant on the `ServiceMonitor`.** The obvious move, and
  [ADR 004](004-scrape-config-via-prometheus-crds.md) rules it out: a module declares scraping
  through its chart's `serviceMonitor.enabled` and nothing else, and a `ServiceMonitor`'s own
  metadata labels are read by whoever selects the CR and never reach a series.
- **One collector per tenant**, each with its own fixed header. It works and it is a collector per
  tenant on a two-node cluster.
- **Leave everything scraped under `default_tenant`.** What happened before, and it makes per-tenant
  limits and retention meaningless for anything that is scraped rather than pushed — which is most
  of what runs here.

## Consequences

- **The label name is duplicated across modules**, once per module that stamps it, because a module
  is applied standalone and cannot read a constant from another. It is not passed as an input on
  purpose: an input for it would be a second place to spell a contract.
- **A chart that exposes neither pod nor service labels cannot carry a tenant.** Its workload is
  collected as the cluster's own, which is the same behaviour it had before this decision, so the
  gap degrades rather than breaks. `podLabels` is the more commonly exposed of the two, which is why
  the pod is the fallback rather than the exception.
- **Setting `tenant` on a running workload restarts it.** It becomes a pod-template label, so the
  Deployment rolls. Trivial, and worth knowing before doing it to cert-manager.
- **A unit whose tenant is the cluster's own is labelled anyway**, since the root passes
  `default_tenant` rather than null. It routes to the same destination the unlabelled case would, and
  what it buys is that `kubectl get svc --show-labels` answers the question without anybody knowing
  the fallback.
- **[ADR 016](016-metrics-is-the-fourth-input.md)'s "one field" no longer holds**; everything else in
  it does, including which modules take the input and what it means.
