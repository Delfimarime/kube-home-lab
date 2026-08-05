# 6. Modules emit their own HTTPRoute

**Status:** accepted · **Date:** 2026-08-05

## Context

Ingress in this cluster is Gateway API on Traefik. Exposing a workload means an `HTTPRoute`.

Charts disagree about how — some have native Gateway API values, some only have `ingress`,
some offer an `extraObjects` escape hatch, and Auditum has no chart at all. Requiring "the
chart must support Gateway configuration" means learning a different values dialect per
workload, and rules out anything whose chart has not caught up.

## Decision

Each module emits its own `HTTPRoute` as a `kubernetes_manifest`, driven by one variable
shape used everywhere:

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

## Rationale

One code path for chart-based and chartless workloads. No per-chart archaeology. The route
is ~15 lines and the same 15 lines everywhere.

## Consequences

- The route does not appear in Argo CD's resource tree for its Application, and Argo CD will
  not self-heal it. Accepted: an HTTPRoute is static and nobody hand-edits it.
- `terraform destroy` removes the Application and the route together, so there is no orphan
  in the normal path. Deleting an Application by hand would leave one.
- Backends are unexposed by simply not being passed a gateway. In the observability module,
  `var.gateway` means Grafana's route, because Grafana is the only exposed surface.
