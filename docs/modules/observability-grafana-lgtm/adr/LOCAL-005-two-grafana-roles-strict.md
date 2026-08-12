# LOCAL-005. Two Grafana roles, read from a claim, and no role means no entry

**Status:** proposed · **Scope:** module — `observability-grafana-lgtm` ·
**Date:** 2026-08-12

## Context

[REQ-01](../../../requirements.md) says a person signs in to an environment's services with one
account, and that workloads do not keep their own user lists.
[ADR 007](../../../adr/007-modules-receive-credentials.md) provides the `oidc` contract that
delivers the issuer, the client id and a Secret reference.

That settles **authentication** and nothing else. Grafana without further configuration will
happily authenticate everyone the issuer vouches for and then hand them all the same default
role — and which default that is, is a chart value nobody chose deliberately. "Signs in" and
"can change the datasources" are different questions, and the contract only answers the first.

Grafana's own model has three org roles — `Viewer`, `Editor`, `Admin` — plus a server-level
`GrafanaAdmin`, assignable from OIDC only when `allow_assign_grafana_admin` is set. Role
assignment is driven by `role_attribute_path`, a **JMESPath** expression evaluated against the
token and userinfo claims.

## Decision

**Two roles, and no third.** When `var.oidc` is set, Grafana recognises exactly:

| Claim value | Grafana org role |
| --- | --- |
| `GRAFANA_ADMIN` | `Admin` |
| `GRAFANA_VIEWER` | `Viewer` |
| *anything else, or absent* | none — the login is refused |

Read from `resource_access.grafana.roles`, overridable by `var.oidc.groups_claim` when a
provider emits them elsewhere:

```ini
role_attribute_path   = contains(resource_access.grafana.roles[*], 'GRAFANA_ADMIN') && 'Admin' || contains(resource_access.grafana.roles[*], 'GRAFANA_VIEWER') && 'Viewer' || ''
role_attribute_strict = true
```

`Editor` is not mapped. `allow_assign_grafana_admin` stays off, so server administration
remains local to the instance and is not something a claim can grant.

**The local login form follows `oidc` by default, and is configurable.** `allow_local_login`
defaults to `null`, meaning derive: on when `oidc` is `null`, off once an issuer is wired.
Setting it `true` alongside `oidc` keeps a break-glass route; setting it `false` with no `oidc`
is refused at plan time, because it admits nobody.

## Rationale

- **Two roles is the number of roles there are.** One person operates these clusters. The
  second role exists for showing someone a dashboard without handing them the datasources.
  `Editor` would be a third name for a person who does not exist, and a permission set nobody
  would be able to describe six months later.
- **`role_attribute_strict = true` is the whole security value of this ADR.** Without it, a
  token carrying no recognised role falls through to Grafana's default role and the person is
  in. Strict turns absence into refusal. That is [REQ-06](../../../requirements.md)'s posture —
  exposure is an act, not the state you end up in by not being mentioned — applied to a person
  rather than a port.
- **Server admin is not delegated.** `allow_assign_grafana_admin` would let a claim grant
  instance-wide administration, including across orgs. There is one org and one operator; the
  capability buys nothing and widens what a misconfigured issuer can do.
- **The expression is JMESPath, and this is worth writing down** because it is the most likely
  thing to be got wrong. A JSONPath-style `$.resource_access.grafana.roles` is syntactically
  accepted and matches nothing, which under strict mode refuses every login — a failure that
  looks like a broken issuer rather than a broken expression.
- **The claim path is the module's, not the contract's.** ADR 007's `oidc` object has no roles
  field, and adding one would be a platform change affecting every module for the sake of one.
  `groups_claim` already exists for "the claim that carries authorization" and serves as the
  override.

## Consequences

- **The issuer must emit the claim, and this module does not make that happen.** It declares
  what it needs; when and by whom it is satisfied is operational, per the third shared-contract
  rule in [the platform spec](../../../platform.md#shared-contracts). A token without the claim
  produces a refused login, not a broken module — but it does mean the first sign-in after
  wiring OIDC will fail until the issuer is configured, and it will fail in a way that looks
  like this module's fault.
- **Granting someone access is a change in the issuer, not in this repo.** That is the point of
  REQ-01, and it means access is not visible in a `git log` here.
- **Wiring `oidc` closes the local login form**, which is what makes REQ-01's "one account" true
  rather than merely available. The consequence is that when the issuer is down — and it likely
  runs in this same cluster — nobody can reach Grafana. `allow_local_login = true` is the
  deliberate exception, and it costs a static password living outside the OIDC path that nobody
  will rotate. Both states are defensible; neither is free, which is why it is an input rather
  than a decision made here on someone's behalf.
- **The derived default is the only one in the module.** Every other input means the same thing
  regardless of its neighbours. This one cannot: `false` is correct with an issuer and a lockout
  without one, so the safe value is a function of `oidc` and a plan-time validation rejects the
  combination that admits nobody. LGTM-13 asserts all three states.
- Adding `Editor` later is a values change and a third clause in one expression. Nothing here
  forecloses it.
