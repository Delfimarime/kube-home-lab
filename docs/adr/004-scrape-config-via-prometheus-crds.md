# 004. Scrape configuration through Prometheus operator CRDs

**Status:** accepted · **Scope:** platform · **Date:** 2026-08-05 ·
revised 2026-08-12 (metrics implementation changed; the decision did not)

> Decided while designing observability, but platform-scoped: it is the reason *every* module
> declares scraping through its own chart's `serviceMonitor.enabled` rather than writing a
> vendor-specific scrape resource. Reversing it changes every module.

## Context

Something has to turn "scrape this service" into the collector's configuration. Without a
discovery mechanism, a collector reads a static file that must be hand-edited and reloaded for
every new service.

Every metrics stack has an answer to this, and they are not the same answer. Some ship their
own scrape CRDs; some read the Prometheus operator's `ServiceMonitor`, `PodMonitor` and
`Probe`; some do both, with a conversion layer between. What they have in common is that
**the Prometheus CRDs are never bundled** — whichever stack is chosen, the CRD bundle is a
separate install.

## Decision

**Workloads declare scraping through their own chart's `serviceMonitor.enabled` switch.** No
module writes a vendor-specific scrape resource, and no module hand-writes scrape config.

The observability module installs the Prometheus operator CRD bundle, and whatever collector
it ships must consume those CRDs — natively if it can, through a conversion layer if it cannot.

## Rationale

The alternative — emitting the metrics stack's own scrape resource and skipping the extra CRDs
— looks leaner until you notice that every upstream chart already has a ServiceMonitor switch.
OpenBao and Zitadel both do. With the CRDs present, those switches work and no scrape resource
is ever written by hand. Without them, each one has to be reimplemented in whatever dialect the
current stack speaks.

The CRD bundle is not redundancy; it is what makes the redundancy unnecessary.

**This is the decision the repo has already tested.** It was made for a metrics stack that
consumed the CRDs through a conversion layer, and survived that stack being replaced by one
that reads them directly — the declarations in every other module did not change, and the
mechanism lost a moving part. A platform decision that gets *simpler* under a different
implementation was made at the right altitude, which is what
[REQ-09](../requirements.md) asks of every choice here.

## Consequences

- An extra CRD bundle in the cluster, installed by the observability module as its own
  Application, and a per-environment prerequisite for anything that declares scraping.
- Workloads with no chart — Auditum — still need a scrape resource written by hand. That is
  one small `ServiceMonitor`, emitted by the module that owns the workload.
- Whether a conversion step exists between the CRDs and the collector is an implementation
  detail of the observability module, not a platform concern. It was present once; it is not
  now.
- Swapping the metrics stack again does not touch the scrape declarations in any other module.
