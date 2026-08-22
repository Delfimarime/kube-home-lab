# LOCAL-001. The OIDC provider is Keycloak

**Status:** accepted · **Scope:** module — `openid-connect-keycloak` · **Date:** 2026-08-15 ·
replaces the Zitadel decision this module previously carried

## Context

[REQ-01](../../../requirements.md) asks for one account per environment.
[ADR 013](../../../adr/013-roles-are-carried-in-the-token.md) goes further and fixes the shape
authorization arrives in: roles named `<SLUG>_<ROLE>`, carried at
`resource_access.<slug>.roles`.

This module previously ran Zitadel, chosen for footprint — a Go binary against a JVM is not a
close contest on a two-node cluster, and [REQ-10](../../../requirements.md) is paid every day in
every environment.

**The claim shape is where that came apart.** `resource_access.<client>.roles` — an array of
role names under a per-client object — is Keycloak's shape. Zitadel emits project roles at
`urn:zitadel:iam:org:project:roles`, as a *map* keyed by role name. `oidc.groups_claim`
overrides the claim *path*, which is the wrong half: the console's role expression is
array-shaped (`contains(resource_access.grafana.roles[*], 'GRAFANA_ADMIN')`) and a map has no
`[*]` to walk. Pointing it elsewhere does not make it work.

That leaves three ways out. Loosen [ADR 013](../../../adr/013-roles-are-carried-in-the-token.md)
to a semantic contract and let each consumer own its extraction expression. Keep the shape and
write a Zitadel action to emit it. Or run the issuer whose native output is already the shape
the platform specified.

## Decision

**Keycloak, deployed by the Keycloak Operator.** The module ships the operator *and* the
environment's initial instance — an operator with no instance is not an identity provider.

## Rationale

- **It makes [ADR 013](../../../adr/013-roles-are-carried-in-the-token.md) true instead of
  aspirational.** That ADR argues `resource_access.<client>.roles` is "the widely-implemented
  shape", so "an issuer can emit it without custom mapping work". That was a claim about
  Keycloak being made while running something else. Now it describes the implementation, and the
  console's expression works with nothing bolted on.
- **A custom claim mapper is a worse place for this to live than a product choice.** A Zitadel
  action emitting a Keycloak-shaped claim is a piece of JavaScript in a console, unversioned,
  invisible to this repository, and load-bearing for every login. Loosening ADR 013 was the
  cleaner alternative, and it was rejected for a different reason: the platform benefits more
  from a predictable claim than from a portable one, and the portability it would buy is
  theoretical until a second issuer exists.
- **The operator makes the instance declarable.** A `Keycloak` resource is reconciled, which is
  what [REQ-08](../../../requirements.md) asks of everything this repo provisions. It also
  sidesteps a chart-sourcing problem that has no clean answer: `codecentric/keycloak` is
  abandoned, and Bitnami's catalogue moved pinned non-`latest` tags behind licensing, which
  collides directly with [ADR 010](../../../adr/010-resources-delivered-via-chart.md)'s rule
  that chart versions are pinned exactly.
- **The realm becomes recordable later without changing anything here.** `KeycloakRealmImport`
  can put clients and roles in git, which is the one thing this platform's identity model most
  lacks. It applies rather than reconciles, so it is a record rather than a reconciled resource
  — and a record is what [REQ-11](../../../requirements.md) is asking for. It is not being taken
  up yet, but the door is a CRD away rather than a product away.

## Consequences

- **The RAM bill is real and is accepted.** A JVM resident set of roughly 512Mi to 1Gi, against
  128–256Mi for what it replaces, on nodes where [REQ-10](../../../requirements.md) is measured
  in exactly this. It buys a correct claim shape and a declarable instance. It is the largest
  standing cost any single decision in this repository has added.
- **`<slug>` and `client_id` are now the same string, and nothing enforces it.** Keycloak keys
  `resource_access` by **client ID**, so [ADR 013](../../../adr/013-roles-are-carried-in-the-token.md)'s
  slug and [ADR 007](../../../adr/007-modules-receive-credentials.md)'s `oidc.client_id` cannot
  differ. They are separate inputs today and a mismatch produces a refused login that looks like
  a broken module.
- **The realm is still click-ops.** Clients, roles and grants are created by hand in Keycloak's
  console, exactly as they were before. `KeycloakRealmImport` is deferred, which means the second
  reason for this decision has not been collected yet, and the identity model still lives
  nowhere. When it is taken up, the seam to be careful about is
  [REQ-05](../../../requirements.md): a realm export embeds client secrets, and a realm resource
  is rendered into an `Application` spec in etcd.
- **The issuer URL now carries a realm.** `https://<hostname>/realms/<realm>` rather than the
  bare host, so `realm` is an input and every consumer's `oidc.issuer_url` changes shape. **It
  defaults to `master`**, revised in place on 2026-08-22 from the opposite position, and the
  reason is that this module creates no realm. `master` is the only realm a fresh Keycloak has,
  so it is the only default that describes something real; naming any other means naming one a
  person creates in the console first. The objection to it stands and is now carried as prose
  rather than as a refusal — `master` administers the server, so signing people in there is a
  choice an environment makes, not a mistake this module can catch.
- **Server-to-server calls stay on the external hostname.** No backchannel split, so Grafana
  reaches this issuer over TLS for the token and userinfo endpoints and needs the lab root in
  its trust store. That makes
  [ADR 018](../../../adr/018-one-trust-bundle-for-the-cluster.md)
  load-bearing for identity rather than convenient.
- **The Zitadel decision is gone rather than superseded.** Nothing implemented it, and
  [docs/README.md](../../../README.md#revising-an-adr) permits revision in place until something
  does. The reasoning that survives — one issuer per environment, no client registration in
  OpenTofu, no client secrets in state — was never Zitadel's and is
  [ADR 007](../../../adr/007-modules-receive-credentials.md)'s.
