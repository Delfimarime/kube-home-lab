# 006. Shared `gateway` input, one shape for every module

**Status:** superseded by [ADR 007](007-modules-receive-credentials.md) ·
**Scope:** platform · **Date:** 2026-08-05 · revised 2026-08-09 · superseded 2026-08-09

This ADR defined the `gateway` input shape: one object type, `null` by default, identical
across every consumer module.

It was superseded rather than kept because it recorded no rejected alternative — the shape
was a contract definition, not a contested decision — and because it defined one of three
inputs whose other two (`database`, `oidc`) were already specified in
[ADR 007](007-modules-receive-credentials.md), in the same shape, for the same reason. All
three are now defined together there, and the platform spec presents them as one table
because that is how they are used.

**The decision itself is unchanged.** `gateway` still has exactly the shape this ADR gave
it. Only its home moved.

## Why this file still exists

[ADR 010](010-resources-delivered-via-chart.md) overturns a premise that originated here:
that every module would emit its own `HTTPRoute` as a Terraform-created
`kubernetes_manifest`, on the reasoning that charts disagreed about Gateway API support and
a Terraform-managed resource was the one path guaranteed to work everywhere. That premise
was reasonable when written and is no longer true of the charts in use. Deleting this file
would delete the thing ADR 010 argues against.
