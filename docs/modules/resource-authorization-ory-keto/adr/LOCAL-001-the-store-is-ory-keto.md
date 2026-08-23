# LOCAL-001. The relationship store is Ory Keto

**Status:** accepted · **Scope:** module — `resource-authorization-ory-keto` · **Date:** 2026-08-23

**The relationship store is Ory Keto, its read API open in-cluster and its write API reachable
only through an access proxy.**

## Decision

**The relationship store is Ory Keto**, one instance, storing its tuples in an external
PostgreSQL, with its **read API reachable in-cluster without authentication** and its **write API
reachable only through an access proxy**.

## Context

[ADR 026](../../../adr/026-roles-decide-the-operation-relationships-decide-the-resource.md) says
resource-level decisions come from a relationship store queried at decision time. This decision is
only about *what provides it*; that anything needs one at all is settled there.

The constraints are the usual ones, plus one that is specific to this capability:

- Two nodes, one operator, weeks where nobody looks. Nothing here scales out.
- PostgreSQL is external ([ADR 008](../../../adr/008-postgresql-is-external.md)), so a store that
  can use it is preferred to one that brings its own.
- **The store must be configurable from outside the cluster.** Relationship data that is
  configuration rather than runtime data — which group administers which tenant — is authored
  somewhere else and applied by a pipeline.
- **The read path is the hot path.** Every authorization decision an application makes is a query
  to this store, and whatever that costs is paid on every request.

## Rationale

- **The read and write APIs are separate listeners on separate ports.** This is the reason. It
  makes the trust boundary and the network boundary the same shape: the hot path can be open to
  the cluster while the path that changes who may do what is fronted by something that
  authenticates. In a store with one API that separation has to be carried by credentials, and a
  credential that is checked is a credential that can be copied into the wrong deployment.
- **The read path costs an application nothing.** No client registration, no token, no refresh, on
  the call made most often. That matters more here than anywhere else, because a token expiring
  unattended in a library that caches badly is an outage in the authorization path.
- **It is actively maintained.** Verified on 2026-08-23: v0.14.0 brought batched tuple insertion
  and deletion, and 2026 releases are still landing correctness fixes in the modelling language —
  most recently rejecting a name declared as both a relation and a permit in one namespace, which
  previously shadowed silently and made checks return wrong answers. That last item is worth
  reading twice: it is the class of defect that fails open.
- **Both candidates use external PostgreSQL**, so [ADR 008](../../../adr/008-postgresql-is-external.md)
  decided nothing between them.

## Alternatives

The candidates were the two mature Zanzibar-derived stores.

| Candidate | Shape | Where it lands |
| --- | --- | --- |
| **Ory Keto** | Go, relation tuples, Ory Permission Language, PostgreSQL. **Read and write APIs on separate ports.** No authentication of its own | chosen |
| **OpenFGA** | Go, relation tuples, its own DSL, PostgreSQL. One API. Built-in authentication — preshared key or OIDC — and conditional relationships | rejected |
| SpiceDB / Permify | The same idea again | not assessed; neither offers something the two above lack at this size |
| A table in an application's own schema | No service to run | is the failure [REQ-13](../../../requirements.md) names, and what [ADR 026](../../../adr/026-roles-decide-the-operation-relationships-decide-the-resource.md) exists to prevent |

**What choosing Keto costs, and it is the whole of the argument against it:** it has **no
authentication of its own, by design** — Ory's position is that it is an internal service and
anything else belongs to a proxy. OpenFGA has authentication in the server, so reaching it by any
route without a valid credential gets you nothing. Here the write path is protected by a proxy and
a network policy, and **a proxy protects a route rather than a service**. That trade was made
knowingly; what it rests on is [LOCAL-002](LOCAL-002-the-write-port-admits-only-its-caller.md).

## Consequences

- **The write path's security is the proxy plus the network policy, and neither is the store.**
  Anything that can reach the write port directly writes what it likes. This is not a weakness in
  Keto — it is the documented design — but it means the protection lives in two places outside it
  and both have to be right.
- **The read API lists as well as checks.** It answers `check` and `expand`, and it also
  enumerates tuples. Leaving it open in-cluster therefore lets any pod read the entire permission
  graph — who may do what to what. This is information disclosure rather than compromise, and it
  is a deliberate choice made for the hot path rather than an oversight.
- **There is no administration UI, and none is planned upstream.** Managing this means the `keto`
  CLI and the APIs. Inspecting why a check returned what it did is a port-forward and a command,
  which is adequate for one operator and would not be for a team.
- **The permission model is not portable.** The Ory Permission Language and Keto's tuple format do
  not transfer to another store; moving would mean rewriting the model and migrating every tuple.
  [REQ-09](../../../requirements.md) is satisfied for consumers, who receive an address — and
  is not satisfied for whoever would do the moving.
- **Tuples are in PostgreSQL and nothing backs it up.** They are the third thing in that database
  that cannot be regenerated from git, after the issuer's realm and the console's alert rules —
  and unlike those two, losing these is a silent widening or narrowing of what people can reach
  rather than an obvious outage.
- **Schema migrations are a step, not a side effect.** The store does not serve before its
  migrations have run, and a version bump is therefore a migration as well as an image change.
