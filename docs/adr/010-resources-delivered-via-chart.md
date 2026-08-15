# 010. Resources are delivered via chart, not OpenTofu-created manifests

**Status:** accepted · **Scope:** platform · **Date:** 2026-08-09 · revised 2026-08-15

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
Auditum has the same problem in a different shape: it has no chart at all, so its resources
were going to be static manifests this repo points an Application at directly, with no way to
receive a OpenTofu-computed value (a hostname, a secret name).

Each module already renders its own `ApplicationSet`, one generated `Application` per chart
([ADR 005](005-modules-are-applicationsets.md)); this decision is about what those generated
`Application`s are allowed to create, not module/chart cardinality.

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
that owns it** — beside the `tofu/` that renders the `ApplicationSet` pointing at it. A module
directory holds exactly those two, so what a module *is* and what it *deploys* are one level
apart and never interleaved, and no chart is shared between modules by accident.

This is deliberately stated without naming a specific resource type: it applies to
`HTTPRoute` today — the case that surfaced it — and to whatever a future module's chart
doesn't cover, without needing a new ADR to say so again.

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
  which routes, and Auditum's resources, were in practice quietly exempted from.

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
- `audit-management-auditum` is the custom case: its `ConfigMap`, `Deployment`,
  `PodDisruptionBudget`, `Service` and (when `gateway` is set) `HTTPRoute` all become
  templates in a chart local to this repo, replacing the earlier "static manifests" approach —
  see its own spec.
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
