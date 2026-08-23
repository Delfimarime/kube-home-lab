# 024. The metrics fact is derived at the root, not declared

**Status:** accepted · **Scope:** platform · **Date:** 2026-08-16 ·
supersedes the root-variable half of [ADR 016](016-metrics-is-the-fourth-input.md)

**The metrics fact is derived at the root from whether a metrics store ships, rather than declared
in a variable.**

## Decision

**The root variable is removed. The root module derives the fact from the metrics store:**

```hcl
metrics = {
  enabled = !var.initial_deployment && try(local.observability.components.metrics, null) != null
}
```

**The module input stays exactly as it is.** `metrics` is still the fourth cross-module input,
still an object with one `enabled` field, still taken by every module whose workload can emit a
`ServiceMonitor` and by no module that cannot. A module is applied standalone and cannot see the
environment's observability configuration; ADR 016 remains the whole truth at that boundary. What
changes is only where the root module gets the value it passes.

**One escape hatch, for one apply: `initial_deployment`, defaulting to `false`.** The CRD bundle
and the workloads declaring `ServiceMonitor`s are separate Applications in separate
ApplicationSets, and nothing orders them against each other — on the apply that first introduces
a metrics store, cert-manager can sync before the CRDs exist. Argo CD retries and converges, so
this is a brake for an operator who would rather not watch that happen, not a repair for a broken
state. Set for the first apply, then unset.

## Context

[ADR 016](016-metrics-is-the-fourth-input.md) made `metrics.enabled` a root variable: an
environment states in its var file that the Prometheus-operator CRDs exist and a collector is
reading them, and every module with a `/metrics` endpoint reads it before declaring a
`ServiceMonitor`. That ADR listed the cost in its own consequences — *"it is a root variable
passed to each module that reads it, so it can disagree with the environment"* — and called
itself the decision most likely to be revisited.

Nothing about it needed to be guessed. The CRD bundle ships from
[`observability-storage-grafana-lgtm`](../modules/observability-storage-grafana-lgtm/README.md)
and only when that module ships a metrics store; the collector that reads what a `ServiceMonitor`
declares ships from the same place. Both halves of what the flag asserts are true exactly when
`observability.components.metrics` is set
([LOCAL-007](../modules/observability-storage-grafana-lgtm/adr/LOCAL-007-a-signal-is-its-own-configuration.md)),
and false in every other case — including the logs-only environment, which runs the collector and
has no CRDs.

So the environment was being asked to state a fact the root module could already read off the one
input that makes it true. That is the arrangement
[LOCAL-007](../modules/observability-storage-grafana-lgtm/adr/LOCAL-007-a-signal-is-its-own-configuration.md)
removed one module earlier, and the one the console module refused when it took three store
addresses instead of three booleans.

## Rationale

- **The disagreeing pair is gone by construction.** A flag claiming scraping where the CRDs are
  absent fails a sync in a module that has nothing to do with observability, which is the most
  confusing place for that failure to appear. There is now no way to write it down.
- **ADR 016's other stated cost goes with it.** *"Turning metrics off in an environment is now a
  multi-unit edit"* — deleting `components.metrics` now turns off every scrape declaration in the
  same edit that removes the CRDs, which is also the only edit order that was ever safe.
- **The objection ADR 016 raised against deriving does not apply to this direction.** It argued
  correctly that a collector is discovered, not dialled, so no address exists for a module to be
  handed — and concluded a boolean was therefore right. That is still true of the *module's*
  input. It says nothing about where the root module reads the boolean from, which is all this
  changes.
- **An environment whose CRDs come from elsewhere can no longer say so.** A cluster running its
  own Prometheus operator could previously set `metrics.enabled = true` with no observability
  configured at all. It cannot now, and that is accepted rather than regretted: the claim was
  unverifiable, and being unverifiable is what made it worth removing. The rejected alternative
  in ADR 016 — an unconditional CRD module — is what to reach for if that environment ever
  exists, and it is a larger change than putting the flag back.

## Alternatives

- **Keep the root variable**, as [ADR 016](016-metrics-is-the-fourth-input.md) had it. Its own
  consequences named the cost — *"it is a root variable passed to each module that reads it, so it
  can disagree with the environment"* — and called itself the decision most likely to be revisited.
- **Have each module detect the CRDs.** A module is applied standalone against an Argo CD API and
  cannot see the cluster's CRDs at plan time.
- **Derive it from a different signal** — the CRD Application's health, say. That is a runtime fact
  read at plan time, which is the coupling [ADR 020](020-one-root-module.md) removed.

## Consequences

- **A var file that sets `metrics` fails to plan**, with `unsupported argument`. The loud break
  is the intended one.
- **This is not a no-op refactor.** `metrics.enabled` defaulted to `false`, so an environment
  that ships a metrics store and never set the flag starts rendering `ServiceMonitor`s on
  cert-manager and the console. That is the point of the change, and it is a real diff in what is
  applied.
- **`initial_deployment` is the only remaining way to hold scraping back**, and it holds *all* of
  it back. Left set, it describes an environment that ships a metrics store and scrapes nothing
  into it, which is not a state anyone wants and is not prevented — the variable's own
  documentation is where that is said.
- **[ADR 004](004-scrape-config-via-prometheus-crds.md) is unchanged**, and so is every module's
  spec: which modules take the input, and what they do with it, is exactly as before.
