# 6. Shared `gateway` input, one shape for every module

**Status:** accepted · **Date:** 2026-08-05 · revised 2026-08-09

## Context

Ingress in this cluster is Gateway API on Traefik. Exposing a workload means an `HTTPRoute`.
Every consumer module needs a way to say "expose me, or don't" without the caller having to
learn how each chart's own values happen to be shaped.

## Decision

Every consumer module takes the same optional `gateway` input:

```hcl
variable "gateway" {
  type = object({
    name         = string
    namespace    = string
    hostname     = string
    section_name = optional(string)
  })
  default = null   # null → not exposed
}
```

`null` is the default, so "not exposed" is the absence of configuration rather than a flag.

How a module turns this variable into an actual `HTTPRoute` is a separate decision — see
[ADR 10](0010-resources-delivered-via-chart.md).

## Rationale

One input shape means no per-chart archaeology at the call site: every module reads
`var.gateway` the same way, regardless of what its own chart expects internally.

## Consequences

- Backends stay unexposed by simply not being passed a gateway. In the observability module,
  `var.gateway` means Grafana's route, because Grafana is the only exposed surface.
- Hostnames are typically defined once as `root.hcl` locals and fed to both a provider and its
  consumers, so both sides agree on the same value (see
  [ADR 7](0007-modules-receive-credentials.md)).
