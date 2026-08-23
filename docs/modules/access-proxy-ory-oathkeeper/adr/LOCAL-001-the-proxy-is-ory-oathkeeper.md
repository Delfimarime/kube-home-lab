# LOCAL-001. The access proxy is Ory Oathkeeper, and it protects a set it is told

**Status:** accepted · **Scope:** module — `access-proxy-ory-oathkeeper` · **Date:** 2026-08-23

**The access proxy is Ory Oathkeeper, and it protects whatever set of services it is given rather
than a named one.**

## Decision

**The access proxy is Ory Oathkeeper**, and **it takes the set of services it protects as an
input** rather than naming one.

Each protected surface is one access rule: an upstream address, a URL and method match, and its
own JWT authenticator carrying that surface's issuer, audience and required scopes. The module
renders the rules as part of its own deployment, so the routing policy ships with the proxy rather
than being applied to it afterwards.

## Context

[ADR 027](../../../adr/027-a-machine-caller-is-authorized-by-scope.md) says a machine caller is
authorized by scope and audience. Something has to check that, and it cannot be the workload
behind it — the first workload that needs this authenticates nobody at all.

So the check belongs in front, in a proxy that terminates the request, validates the token against
the environment's issuer, and forwards only what passes. The Gateway routes to the proxy; the
proxy routes to the workload.

This is the first component here whose whole job is security. Everything else authorizes access to
itself.

## Rationale

- **A proxy that names its upstream is a proxy that has to change to protect a second thing.**
  Taking a map of services makes the second one a root-level edit
  ([§4.2](../../../../CONSTITUTION.md#4-composition)) and keeps this module ignorant of what it
  guards, which is what makes the capability half of its name mean anything — Envoy's external
  authorization, Pomerium, or a `ForwardAuth` middleware all fit the same shape.
- **Its rule model is per-route in every dimension, which is what the design needs.** Verified on
  2026-08-23: each rule carries its own `upstream.url`, its own authenticators, its own authorizer,
  its own mutators and its own error handlers, and matches on URL — glob or regexp — plus method.
  A rule's `jwt` authenticator takes `jwks_urls`, `trusted_issuers`, `target_audience`,
  `required_scope`, `allowed_algorithms` and `token_from`. Two surfaces on one host, with different
  audiences and different scopes, is the ordinary case rather than a workaround.
- **Rendering the rules with the deployment makes them reconciled rather than applied.** Rules that
  arrive by some other path are configuration that drifts from what the repository says, which is
  [REQ-08](../../../requirements.md) failing at the place where failing means an authorization
  boundary that is not the one anybody reviewed.
- **It is actively maintained.** Verified on 2026-08-23: v26.2.0 in March 2026, and v25.4.0 moved
  it into Ory's monorepo. This was checked because an unmaintained proxy in the authorization path
  is a worse liability than an unmaintained anything else here.

## Alternatives

- **Put the check in the workload.** Not available: the first workload that needs this
  authenticates nobody at all, which is why it needs a proxy rather than a configuration flag.
- **Name the upstream in this module.** Simpler to write and it makes protecting a second service
  a change to this module rather than to the composition — which is the coupling
  [§4.2](../../../../CONSTITUTION.md#4-composition) exists to avoid.
- **Use the Gateway itself.** Traefik can do forward authentication, and it is a per-environment
  prerequisite this repository never provisions
  ([§1.1](../../../../CONSTITUTION.md#1-boundaries)) — so the boundary would live in something
  outside this repository's control, described nowhere it can be reviewed.

## Consequences

- **A wrong rule is a silent authorization failure.** A too-narrow match refuses traffic, which is
  visible immediately. A too-broad one — a `<.*>` reaching further than intended, a missing
  `target_audience`, a method omitted from the list — forwards requests nobody authorized, and
  looks exactly like a working configuration. **The rules are the security boundary**, which puts
  them squarely in scope for this module's acceptance criteria rather than being treated as
  configuration.
- **Authorization here is scope-level and nothing finer.** The `jwt` authenticator validates
  issuer, audience and the scope claims — `scp`, `scope` and `scopes` — and **cannot match a
  nested claim** such as `resource_access.<slug>.roles`. Reaching one means the `remote_json`
  authorizer, whose payload template does see the full claim set, calling a service written to
  answer the question. That component is deliberately not built
  ([ADR 027](../../../adr/027-a-machine-caller-is-authorized-by-scope.md) records why), so this
  module has no way to distinguish two callers holding the same scope.
- **Do not reach for the bundled Keto authorizer.** Oathkeeper ships `keto_engine_acp_ory`, and
  the obvious idea — have the proxy ask the relationship store whether a caller may write to the
  relationship store — does not work: it targets an access-control-policy API that the current
  store no longer serves. The upstream request to implement it for later versions was closed
  without one. It is recorded here because it is the first thing anyone will try.
- **The proxy's own administration API must not be routed.** It exposes the rule set, which
  describes every boundary this module enforces. Only the proxy port belongs behind the Gateway.
- **This module is in the path of every protected request.** It being down is those surfaces being
  down, and it being misconfigured is worse than that. Nothing here is highly available, which is
  the standing trade in these environments
  ([§1.4](../../../../CONSTITUTION.md#1-boundaries)) — but the consequence lands harder on a
  component whose failure mode includes admitting somebody.
