# 4. Scrape configuration through Prometheus operator CRDs

**Status:** accepted · **Date:** 2026-08-05

## Context

Something has to turn "scrape this service" into vmagent's configuration. Without an
operator, vmagent reads a static file that must be hand-edited and reloaded for every new
service.

The VictoriaMetrics operator offers its own CRDs (`VMServiceScrape`, `VMPodScrape`,
`VMRule`) and also converts the Prometheus operator's equivalents (`ServiceMonitor`,
`PodMonitor`, `PrometheusRule`). Crucially, **the Prometheus CRDs are not shipped with the
VictoriaMetrics operator** — they must be installed separately.

## Decision

The observability module installs the Prometheus operator CRD bundle and enables the
VictoriaMetrics operator's conversion. Workloads declare scraping through their own chart's
`serviceMonitor.enabled` switch.

## Rationale

The alternative — emitting `VMServiceScrape` and skipping the extra CRDs — looks leaner
until you notice that every upstream chart already has a ServiceMonitor switch. OpenBao and
Zitadel both do. With the CRDs present, those switches work and no scrape resource is ever
written by hand. Without them, each one has to be reimplemented as a `VMServiceScrape`.

The CRD bundle is not redundancy; it is what makes the redundancy unnecessary.

## Consequences

- An extra CRD bundle in the cluster, and a conversion step as a moving part.
- Workloads with no chart — Auditum — still need a scrape resource written by hand. That is
  one small resource, emitted by the module that owns the workload.
- If VictoriaMetrics is ever swapped for Prometheus, the scrape declarations survive
  unchanged.
