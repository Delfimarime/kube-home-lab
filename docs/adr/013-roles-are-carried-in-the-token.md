# 013. Authentication and authorization: roles are carried in the token

**Status:** accepted · **Scope:** platform · **Date:** 2026-08-13

**What a person may do comes from the token — roles named `<SLUG>_<ROLE>` at `resource_access.<slug>.roles`, and absence is a denial.**

## Decision

**Roles are named `<SLUG>_<ROLE>` and carried in the token at
`resource_access.<slug>.roles`.**

`<slug>` is the consuming system's short name — `grafana`, `argocd` — lowercase in the claim
path and uppercase in the role name. `<ROLE>` is `ADMIN` or `VIEWER`.

**The slug is the OIDC client ID**, not a label chosen alongside it. Keycloak keys
`resource_access` by client ID, so a slug that differs from
[ADR 007](007-modules-receive-credentials.md)'s `oidc.client_id` names an object that does not
exist.

```
resource_access.grafana.roles = ["GRAFANA_ADMIN"]
```

Three rules follow, and hold for every consumer:

1. **A consumer maps these to its own native roles**, and to nothing else. What `ADMIN` means
   is the product's business; which claim carries it is not.
2. **A principal carrying no recognised role is refused**, not admitted at a reduced level.
   Absence is a denial.
3. **Two roles is the baseline.** A consumer that genuinely needs more may define them, but
   keeps the `<SLUG>_<ROLE>` shape and the slug scoping.

A module declares the claim it reads; whether the issuer emits it is operational, per the third
shared-contract rule in [the platform spec](../platform.md#contracts). Where an issuer
puts roles somewhere else, `oidc.groups_claim` overrides the path.

## Context

[ADR 007](007-modules-receive-credentials.md) gives every consumer module the same `oidc`
input — issuer, client id, a Secret reference — and that settles **authentication**. A person
signs in once per environment, and no workload keeps its own user list
([REQ-01](../requirements.md)).

It settles nothing about **authorization**. A workload that authenticates everyone the issuer
vouches for, and then decides for itself what each of them may do, has simply moved its
permission list rather than removed it — which is the failure
[REQ-13](../requirements.md) names.

Left to each module, this would go three ways at once: every consumer picking its own claim
name, its own role vocabulary, and its own answer for a principal carrying no role at all. The
third is the dangerous one, because the comfortable default — fall back to a viewer role, let
them in — is the one a chart picks when nobody chooses.

## Rationale

- **One shape means a reader can predict any service's claim without opening its module.** That
  is the same argument ADR 007 makes for one input shape, applied one layer up: the alternative
  is per-service archaeology, in the issuer's console instead of the call site.
- **The slug scopes the role.** `GRAFANA_ADMIN` and `ARGOCD_ADMIN` cannot be confused, and
  `resource_access.<slug>` keeps them in separate objects, so granting one grants exactly one.
  A flat `roles: ["admin"]` claim would make every consumer trust every other consumer's grant.
- **`resource_access.<client>.roles` is the widely-implemented shape**, so an issuer can emit it
  without custom mapping work, and a future issuer will understand it too — which is
  [REQ-09](../requirements.md) applied to identity.
- **Deny by default is the entire security value.** Without rule 2, a token missing its claim
  falls through to whatever the product's default role is, and the person is in. This is
  [REQ-06](../requirements.md)'s posture — access is an act, not the state you reach by not
  being mentioned — applied to a person rather than a port.
- **Two roles is the number this lab has.** One operator, and occasionally someone who should
  see a dashboard without being able to change what it queries. A third role would be a name
  for a person who does not exist.

## Alternatives

- **A flat `roles` claim** — `roles: ["admin"]`, unscoped. Simpler to emit and it makes every
  consumer trust every other consumer's grant: `admin` anywhere is `admin` everywhere. Scoping by
  client is what makes a grant mean one thing.
- **Groups instead of roles.** Widely used, and it moves the vocabulary into a directory structure
  whose shape the issuer owns and no consumer can predict. `oidc.groups_claim` exists so an issuer
  that works this way can still be wired, without making it the convention.
- **Let each consumer decide**, mapping whatever its chart supports. Three consumers, three claim
  names, three answers for a principal carrying no role — and the third is the dangerous one,
  because the comfortable default is to let them in.

## Consequences

- **The issuer must emit the claim, and no module makes that happen.** Wiring `oidc` to a
  consumer before configuring roles in the issuer produces a refused login — correct behaviour
  that will look like a broken module the first time it happens.
- **Granting someone access is a change in the issuer, not in this repository.** That is what
  REQ-01 asks for, and it means access is not visible in a `git log` here.
- **Adding a consumer means adding its role set to the issuer**, by hand, in the same console
  where its client is registered ([ADR 007](007-modules-receive-credentials.md)). At the ~fifteen
  clients where that ADR says to revisit registration, this is part of the same bill.
- **How the claim is evaluated is per-product and not specified here.** Grafana reads it with a
  JMESPath expression and no `$.` prefix; another consumer may want a different form of the same
  path. The claim's *shape* is the contract; parsing it is the module's business.
- **A consumer with no role model ignores this ADR**, and says so in its own spec. A workload
  that authenticates nobody has nothing here to apply.
- Adding a third role later is a values change in one consumer, not a change to this decision,
  as long as it keeps the shape.
- **`<slug>` and `oidc.client_id` are two inputs holding one value, and nothing compares them.**
  A mismatch produces a token whose `resource_access` has no entry under the slug the consumer
  reads, so the consumer sees no role and refuses the login — correct behaviour by rule 2, and
  indistinguishable from a person who genuinely has no role. The check belongs in each
  consumer, since no single module sees both.
- **The role catalogue is not declared anywhere.** This ADR fixes the shape of a set whose
  members exist only in the issuer's console — see
  [`openid-connect-keycloak`'s open items](../modules/openid-connect-keycloak/README.md#open-items).
  A convention with no instance is a convention nobody can check against.
