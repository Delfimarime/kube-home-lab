# LOCAL-004. Storage splits from the console, and the receiver gets a route

**Status:** accepted · **Scope:** module — `observability-storage-grafana-lgtm` ·
**Date:** 2026-08-15

## Context

`observability-grafana-lgtm` rendered six Applications covering three jobs: collecting
telemetry, storing it, and looking at it. That was defensible while all six shipped together
and nothing was exposed. Two things stopped being true.

**The dependencies are not shared.** Grafana requires PostgreSQL — no SQLite fallback, so it
does not start without it — plus an issuer, a route, and a person holding a role. Mimir, Loki
and Tempo require none of those. A cluster that wants to *ingest* telemetry was being told it
needed a database, and the reason was one of the six Applications.

**Something outside the cluster needed to push.** A VM or a laptop cannot be scraped and cannot
reach a `ClusterIP`, so the OTLP receiver needed a route. Once it has one, the module has an
exposed surface that is not Grafana — and `var.gateway` had, up to then, meant "Grafana's
route" precisely because Grafana was the only exposed thing
([ADR 007](../../../adr/007-modules-receive-credentials.md) says so in as many words).

Four shapes were real:

- **Keep one module.** Nothing to build. The database stays mandatory for an environment that
  only wants to collect, and `var.gateway` has to mean two different routes at once.
- **Split into storage and console.** The seam falls exactly on the PostgreSQL-and-identity
  boundary, which is also the read/write boundary.
- **Split three ways** — collector, stores, console. The collector and the stores are driven by
  the same three flags and are useless apart; separating them would produce two modules that must
  always agree and a third contract to keep them agreeing.
- **One console reading stores in other clusters.** Rejected on sight:
  [ADR 011](../../../adr/011-environments-are-clusters.md) makes an environment a cluster and
  says there is no cross-environment view by design.

A fifth question came with the second shape: what the console is told. Three booleans mirroring
the flags, or three addresses.

## Decision

**Two modules.** This one keeps the collector and the three stores. Grafana becomes
`observability-console-grafana`, which takes `database`, `oidc` and its own `gateway`. This
module loses `database` and `oidc` entirely.

**The console is told addresses, not flags.** `metrics_url`, `logs_url` and `traces_url` are
outputs here and nullable inputs there. Which datasources exist and which correlation links are
wired is derived from which of the three is non-null.

**`var.gateway` means the OTLP receiver's route**, since nothing else here is exposed. No new
input: the contract's shape already carries everything a route needs, and a second variable of
the same shape would be two ways to say one thing.

**The route is OTLP/HTTP on 4318, one rule per enabled signal** — `/v1/metrics`, `/v1/logs`,
`/v1/traces` — rendered by `k8s-monitoring-routed`, a chart local to this module that declares
`k8s-monitoring` as a Helm dependency and adds the template. That is the **wrapped** case of
[ADR 010](../../../adr/010-resources-delivered-via-chart.md), used here for the first time in
this repository.

## Rationale

- **The split is the dependency graph, not a filing decision.** Everything Grafana needs to run,
  nothing else here needs; everything here needs, Grafana does not. A seam that falls on a
  hard external dependency is one that will still be in the right place after the products
  change.
- **Addresses cannot disagree with reality; booleans can.** "Metrics are switched on" and "there
  is a Mimir at this URL" are two truths that a split module could hold separately and get wrong
  separately. A value that is either an address or `null` collapses them into one, and the four
  correlation links then derive from exactly the same fact that put the store there. The same
  argument was later turned inward on this module's own inputs, which is how the three
  `enable_*_support` flags it was written against stopped existing
  ([LOCAL-007](LOCAL-007-a-signal-is-its-own-configuration.md)).
- **Three ways would have been one seam too many.** The collector exists to feed the stores and
  follows the same components; the third module would have had no independent reason to change.
- **`gateway` did not need widening, only re-reading.** The contract says *emit a route for this
  workload*. It never said the workload had to be a UI — that was a fact about the modules that
  existed, and ADR 007 recorded it as such rather than as a rule.
- **HTTP over gRPC, for the route only.** Exposing 4317 needs an `h2c` backend protocol on the
  Service and a `GRPCRoute` instead of an `HTTPRoute` — two implementation-specific behaviours
  to bet on, for a transport advantage that is invisible to a laptop on a home network. 4317
  stays the in-cluster address, where neither problem arises.
- **Per-signal paths are not the per-signal names
  [LOCAL-003](LOCAL-003-scrape-first-one-otlp-address.md) refused.** That decision rejected
  `traces.`, `logs.` and `metrics.` hostnames because all three would resolve to one socket and
  invent a distinction living a layer down. `/v1/traces` is where the OTLP/HTTP specification
  puts the distinction itself. The route surface therefore matches the flags, and pushing a
  signal this environment does not store returns `404` instead of being accepted and dropped.
- **No fourth input naming which signals to expose.** `gateway` being set is already the
  deliberate act [REQ-06](../../../requirements.md) asks for, and the flags already say which
  stores exist. A knob is turned once something hurts.

## Consequences

- **Two `module` blocks in the root module, with one reference**: the console reads this module's
  three addresses. One direction, no cycle, and an environment may ship this module alone.
- **An environment can now collect telemetry without a PostgreSQL.** It gets no way to look at
  it, which is honest — that is what the second unit is for.
- **[ADR 010](../../../adr/010-resources-delivered-via-chart.md)'s closing line is no longer
  true.** It ends "No module needs the wrapped case yet." This one does, and the wrapper carries
  two versions — its own and the upstream dependency's — so a chart bump is two edits.
- **Scenario IDs have gaps.** Those that moved to the console took new `CON-` numbers; three
  that asserted something about both halves at once were retired rather than split, because an
  ID is never reused for a different assertion.
- **[LOCAL-001](LOCAL-001-grafana-lgtm-stack.md) stays here and covers both modules**, since it
  argues for Grafana as the query surface as well as for the three stores. A module ADR is local
  to its module, so the console spec restates the pairing in prose rather than citing it. That
  is the one place this split strains a convention, and it is cheaper than splitting a single
  coherent argument in half.
- **Switching a signal off now removes two things**, a store and a route rule. The destructive
  edge on the flags is unchanged in kind and slightly wider in reach.
- **Reversible, but not cheaply.** Merging the two back means one module whose `gateway` again
  serves only Grafana and whose OTLP route needs an input of its own — which is the design this
  decision replaced. The addresses-not-flags choice is the part worth keeping either way.
