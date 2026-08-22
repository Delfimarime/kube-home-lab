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
cert-manager's does. With the CRDs present, those switches work and no scrape resource is ever
written by hand. Without them, each one has to be reimplemented in whatever dialect the current
stack speaks.

The CRD bundle is not redundancy; it is what makes the redundancy unnecessary.

Stating it in the Prometheus dialect rather than a vendor's is what makes it survivable: the
metrics stack is the piece most likely to be swapped, and every other module's scrape
declaration should be indifferent to that — which is [REQ-09](../requirements.md) applied to
the one thing every module touches.

## Consequences

- An extra CRD bundle in the cluster, installed by the observability module as its own
  Application, and a per-environment prerequisite for anything that declares scraping.
- Workloads with no chart — Auditum — still need a scrape resource written by hand. That is
  one small `ServiceMonitor`, emitted by the module that owns the workload.
- Whether a conversion step exists between the CRDs and the collector is an implementation
  detail of the observability module, not a platform concern. It was present once; it is not
  now.
- Swapping the metrics stack again does not touch the scrape declarations in any other module.
