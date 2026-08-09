# LOCAL-001. OIDC provider: Zitadel

**Status:** accepted · **Scope:** module — `openid-connect-zitadel` · **Date:** 2026-08-05

That this decision is module-scoped is itself the evidence that
[ADR 007](../../../adr/007-modules-receive-credentials.md) works: swapping the identity
product touches nothing outside this folder.

## Context

The lab needs one identity provider so Grafana, Argo CD and everything after them stop
having their own logins. Constraints: a tiny k3s cluster, one human, and whatever runs here
has to still be understandable after six months of neglect.

## Options

| | Workloads | RAM idle (rough) | Config-as-code | Notes |
| --- | --- | --- | --- | --- |
| **Zitadel** | 1 + Postgres | ~300 MB | Terraform provider | Go, OIDC + SAML, admin UI, management API |
| Keycloak | 1 + Postgres | ~600 MB–1 GB | realm JSON, TF provider | Already known. JVM. The safe answer |
| Authentik | server + worker + Postgres + **Redis** | ~1–1.5 GB | blueprints, TF provider | 4 workloads. Forward-auth outposts are its one real edge |
| Ory (Hydra + Kratos) | 2 + Postgres | ~150 MB | config files, TF provider | Cheapest RAM, no user store, **you write the login UI** |

## Decision

Zitadel, chart `11.0.0-beta.4` (appVersion v4.14.0), pinned exactly.

It is the only option that is both complete (user store, admin UI, OIDC and SAML, first-class
Terraform provider) and small (one Go process plus Postgres). Authentik costs a Redis and a
worker for a forward-auth feature this lab does not need yet — the services here speak OIDC.
Ory is cheapest on paper and most expensive in hours, because "no login UI" means writing one.

Keycloak was the near-miss, and the argument for it was real: it is already known, which
normally beats every benchmark. It loses on standing cost — roughly double the memory, all
day, every day, on a node that has a finite amount of it — for capabilities this lab does not
use. The unfamiliarity is a one-time cost; the JVM is a permanent one. That cost is now paid
once per environment ([ADR 011](../../../adr/011-environments-are-clusters.md)), which makes
the gap wider, not narrower.

A beta chart is accepted deliberately: this is a homelab, and a breakage is noticed rather
than escalated. The version is pinned exactly so an upgrade is a deliberate edit.

## Consequences

- PostgreSQL is required and is supplied from outside this project — see
  [ADR 008](../../../adr/008-postgresql-is-external.md). Losing that database loses every
  account in that environment.
- Learning curve: Zitadel's org/project/instance model is not Keycloak's realm/client model.
- The chart defaults to a highly-available layout and must be scaled to one replica.
- Install runs init and setup Jobs through Helm hooks, which Argo CD translates to its own
  hooks. Expect to fight sync ordering once.
- A masterkey Secret must exist before first install. The module declares it as a required
  input and does not care who creates it or when — see
  [ADR 007](../../../adr/007-modules-receive-credentials.md).
- Each environment runs its own issuer, so accounts do not carry between environments
  ([ADR 011](../../../adr/011-environments-are-clusters.md)).
- The module registers no clients and holds no client secrets — see
  [ADR 007](../../../adr/007-modules-receive-credentials.md).
- If a service without OIDC support ever shows up, it needs oauth2-proxy in front of it.
  Two or three of those and this decision is worth revisiting against Authentik.
