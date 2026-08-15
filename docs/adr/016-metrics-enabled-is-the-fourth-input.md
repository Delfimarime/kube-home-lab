# 016. `metrics_enabled` is the fourth cross-module input

**Status:** accepted · **Scope:** platform · **Date:** 2026-08-15

## Context

[ADR 004](004-scrape-config-via-prometheus-crds.md) says a workload declares scraping through
its own chart — `serviceMonitor.enabled`, and nothing else. That produces a `ServiceMonitor`,
which is a Prometheus-operator CRD, which exists in a cluster only when
[`observability-storage-grafana-lgtm`](../modules/observability-storage-grafana-lgtm/README.md)
installed the bundle — and it installs it only when metrics are switched on. An environment
shipping no observability module at all has none.

So a module cannot simply always declare scraping. Applying a `ServiceMonitor` to a cluster
without the CRD fails the sync outright.

This has been solved once per module and named nowhere.
[`openid-connect-keycloak`](../modules/openid-connect-keycloak/README.md) takes a
`metrics_enabled` input; so does
[`certificate-management-cert-manager`](../modules/certificate-management-cert-manager/README.md).
Neither appears in the platform spec's contracts, and its component list names neither as
something those modules consume. [ADR 007](007-modules-receive-credentials.md) says *every*
consumer takes the same three optional inputs, which has quietly not been the whole truth.

## Decision

**`metrics_enabled` is a named platform input**, taken by every module whose workload can emit
a `ServiceMonitor`. It is a `bool`, defaulting to `false`, and it is listed in
[the platform spec](../platform.md#contracts) beside the three contracts.

**It is not a fourth contract, and does not become one.** The three carry a reference to
something addressable — a Gateway, a database, an issuer. This carries a fact about the
environment.

**A module with no metrics endpoint does not take it**, and says so in its spec rather than
accepting it and ignoring it.

## Rationale

- **A boolean is right here, where an address was right for the console.** There is nothing to
  address: a collector *discovers* `ServiceMonitor`s, it is not dialled. No URL exists that a
  module could be handed, so the objection raised elsewhere against booleans — that a flag and
  the thing it describes can disagree — has no better alternative to be measured against here.
- **Naming it stops it being a per-module accident.** Three modules take it today and every
  future module with a `/metrics` endpoint will. An input that crosses module boundaries and
  appears in no shared document is one that will be spelled differently the fourth time.
- **The alternative was considered and it is not obviously worse.** Installing the
  Prometheus-operator CRD bundle unconditionally, in a unit of its own, would let every module
  always set `serviceMonitor.enabled`; an orphaned `ServiceMonitor` with no collector reading it
  is inert. It was rejected because it makes every environment carry observability CRDs whether
  or not it ships observability, and because it moves CRD ownership out of the module that
  installs the collector and into a unit that exists for no other reason. Neither objection is
  crushing, and this is the decision most likely to be revisited.
- **The flag says more than "the CRDs exist".** It also says a collector is running that will
  read what the `ServiceMonitor` declares. A module declaring scraping into a cluster with the
  CRDs but no collector produces an object nobody reads, which is worse than a failure because
  it looks like it worked.

## Consequences

- **There are four cross-module inputs, not three**, and
  [the platform spec](../platform.md#contracts) says so. `Every consumer module takes the
  same three optional inputs` was true of wiring and never true of everything.
- **It is copied by hand like everything else** ([ADR 015](015-units-are-wired-by-hand.md)), so
  it can disagree with the environment. Two failure modes, and they are usefully different:
  claiming scraping where the CRDs are absent fails the sync loudly; claiming it where the CRDs
  exist but no collector runs produces an object nobody reads, silently. The loud one is the
  common one.
- **A module's spec states whether it takes this input**, in the same place it states which
  contracts it takes. The platform spec names the input and the mechanism; which modules use it
  is not restated there.
- **Turning metrics off in an environment is now a multi-unit edit.** Every module that declares
  scraping has to be told, or its next apply fails once the CRDs go. That is the cost of the
  flag, and the unconditional-CRD alternative above is what removes it.
- **[ADR 004](004-scrape-config-via-prometheus-crds.md) is unchanged.** How scraping is
  declared was never in question; this records what a module needs to know before it may
  declare it.
