# 010. Resources are delivered via chart, not OpenTofu-created manifests

**Status:** accepted · **Scope:** platform · **Date:** 2026-08-09 · revised 2026-08-15

**Every in-cluster resource is owned by a generated `Application`, and OpenTofu creates no bare Kubernetes object.**

## Decision

**Each chart's generated Argo CD `Application` owns every in-cluster resource it needs.
OpenTofu never creates a bare Kubernetes object directly.** Each module resolves this per
chart, in order of preference:

1. **Native** — the workload's own chart already renders what's needed (e.g. Gateway API
   resources) from its values. OpenTofu sets those values on the existing chart. Nothing else
   to build.
2. **Wrapped** — the workload's chart doesn't cover it. A chart local to this repo declares
   the workload's chart as a Helm dependency (`Chart.yaml` → `dependencies`) and adds the
   missing template(s) on top (e.g. `templates/httproute.yaml`). The Application points at
   this local chart instead of the upstream repo.
3. **Custom** — the workload has no chart at all. A chart local to this repo is authored from
   scratch, covering every resource the workload needs.

**A chart this repo authors, wrapped or custom, lives at `helm/<chart-name>/` inside the module
that owns it** — beside the OpenTofu that renders the `ApplicationSet` pointing at it. What a
module *is* and what it *deploys* stay one level apart and never interleaved, and no chart is
shared between modules by accident.

This is deliberately stated without naming a specific resource type: it applies to
`HTTPRoute` today — the case that surfaced it — and to whatever a future module's chart
doesn't cover, without needing a new ADR to say so again.

## Context

[ADR 006](006-shared-gateway-input.md) originally had every module emit its own `HTTPRoute` as
a `kubernetes_manifest` — a resource OpenTofu creates directly, outside the module's Argo CD
`Application`. That was deliberate at the time: charts disagreed on Gateway API support, and a
OpenTofu-managed resource was the one code path guaranteed to work everywhere, chart-based or
not.

That premise no longer holds for the charts actually in use here. `grafana` (`route.main`)
renders Gateway API resources from its own values today, and where a chart does not, a thin
local one adds the template rather than OpenTofu reaching past the Application.
And the underlying problem was never
route-specific: a `kubernetes_manifest` resource is, by construction, outside the Application
it conceptually belongs to — untracked in Argo CD's resource tree, and not self-healed by it.
A workload with no chart at all has the same problem in a different shape: its resources become
static manifests this repo points an Application at directly, with no way to receive a
OpenTofu-computed value (a hostname, a secret name). One module was in that position when this
was written.

Each module already renders its own `ApplicationSet`, one generated `Application` per chart
([ADR 005](005-modules-are-applicationsets.md)); this decision is about what those generated
`Application`s are allowed to create, not module/chart cardinality.

## Rationale

- The gap was never really about routes — it's that a OpenTofu-created resource can't be
  owned by an Application. Stating the decision at that level means it holds the next time a
  workload needs something its chart doesn't provide.
- Native first keeps the cost near zero wherever a chart already does the job — no wrapper,
  nothing extra to maintain.
- Wrapping beats reinventing: Helm's dependency mechanism lets a thin local chart add one
  template on top of an upstream chart instead of re-authoring the whole workload.
- This also closes a gap in [the platform spec's](../platform.md) own acceptance
  criterion — every workload owned by an Application, none created directly by OpenTofu —
  which routes, and the resources of any workload carrying no chart, were in practice quietly
  exempted from.

## Alternatives

- **`kubernetes_manifest` per module**, which is what [ADR 006](006-shared-gateway-input.md) had.
  It works regardless of chart support, and by construction the resource sits outside the
  `Application` it belongs to: untracked in Argo CD's resource tree and not self-healed by it. That
  is the failure this decision exists to remove.
- **Static manifests an `Application` points at.** No OpenTofu involvement at all, and no way for
  the manifest to receive a computed value — a hostname, a Secret name — so anything the root
  derives has to be duplicated by hand.
- **Re-authoring an upstream chart** instead of wrapping it. All of the maintenance, none of the
  upstream fixes, and a divergence that is invisible until a version bump.

## Consequences

- `observability-console-grafana` is the native case for its `HTTPRoute` today — no code to
  migrate, since it had no working route mechanism implemented yet.
  `openid-connect-keycloak` is the custom case instead: the Keycloak Operator reconciles a
  `Keycloak` resource and speaks no Gateway API, so a local chart renders both that resource
  and the route beside it.
- **A module can be both cases at once, for different resources.**
  `observability-storage-grafana-lgtm` is custom for its metrics store, where no upstream chart
  covers the deployment mode it needs, and wrapped for its collector, whose chart renders no
  route at all. The three cases are chosen per chart, not per module.
- A per-chart values dialect is now something each module deals with once, for its own native
  case — there's no longer one shared 15-line block reused everywhere. Each module's own spec
  states its case and the values it sets.

- **Chart versions are pinned exactly**, which is what keeps a native chart's Gateway API values
  from changing under us silently; a schema change on upgrade is a deliberate edit, not a
  surprise. That applies to every chart a module references, upstream or local.
- **The wrapped case is in use.** `observability-storage-grafana-lgtm` ships
  `k8s-monitoring-routed`, which declares the upstream collector chart as a Helm dependency and
  adds one route template on top — the collector's chart renders no Gateway API resource for its
  OTLP receiver. This file originally recorded that no module needed the case yet; it now has a
  worked example. The cost it carries is two pinned versions, its own and the dependency's.

*Revised 2026-08-23.* A further bullet here named `audit-management-auditum` as a third custom
case, and the Context named it as the workload with no chart at all. That module was dropped
along with the requirement behind it; the two custom cases above make the same point, and the
Context keeps the shape of the argument because a chartless workload was half of why this
decision was made. Nothing about the decision changed.
