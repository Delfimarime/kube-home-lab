# 005. Modules are ApplicationSets, not Applications

**Status:** accepted · **Scope:** platform · **Date:** 2026-08-05 · revised 2026-08-09

## Context

An earlier scaffold had a shared `argocd-app` module that every unit called with a chart name
and values. The alternative is for each module to render its own Argo CD resources inline.

Modules vary in how many charts they need — one today
([openid-connect-zitadel](../modules/openid-connect-zitadel/README.md)), six
([observability-storage-grafana-lgtm](../modules/observability-storage-grafana-lgtm/README.md)) — and
that count can grow under [ADR 010](010-resources-delivered-via-chart.md)'s wrapped/custom
cases. Modeling a module as a single `Application` only works until it needs a second chart,
at which point it has to migrate to a different Argo CD resource kind — a disruptive change,
not an incremental one.

## Decision

**Every module provisions its own Argo CD `ApplicationSet`**, using a `List` generator with
one static entry per chart the module needs — even when that's a single entry. There is no
shared `ApplicationSet` module; each module still authors its own, inline.

## Rationale

- One Argo CD resource kind for "a module," regardless of how many charts it happens to bundle
  today or later. Adding a second chart to what's currently a one-chart module is a new list
  entry, not a resource-kind migration.
- The `List` generator's entries are static and known at Terraform plan time — previously read
  as a reason *against* `ApplicationSet` ("a generator earns its place when it discovers
  things Terraform does not already know"). That still holds for dynamic generators, but a
  static list needs no discovery to benefit from templating: the entries stay fully visible in
  the module's own Terraform code, just expressed as generator elements instead of `for_each`.
- An `ApplicationSet`'s shared `template` centralizes what used to be repeated per
  `Application` — `project`, `syncPolicy`, common labels — which fixes this ADR's own
  previously named cost of ~25 lines of boilerplate repeated per Application. A `syncPolicy`
  change is now one edit to a module's template, not one edit per chart it contains.

## Consequences

- Every module's Terraform creates exactly one `ApplicationSet`, never a bare `Application`.
- `terraform plan` shows the `ApplicationSet` object and its generator entries — still fully
  declared in the module's HCL — but the `Application`s it expands to are created and
  reconciled by Argo CD's own controller, not directly visible as Terraform-managed resources.
- An `ApplicationSet`'s generated `Application`s are owned by it and are removed with it via
  Argo CD's own garbage collection — `terraform destroy` still only has to remove one object
  per module.
- A global change to `syncPolicy` or labels still touches every module's `ApplicationSet`
  individually — there is no shared module, unchanged from the original decision — but within
  a module it's now one edit, not one per chart.
