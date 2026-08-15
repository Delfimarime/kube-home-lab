# LOCAL-001. Applying the role convention to Grafana

**Status:** accepted · **Scope:** module — `observability-console-grafana` ·
**Date:** 2026-08-12

## Context

[ADR 013](../../../adr/013-roles-are-carried-in-the-token.md) settles the shape:
`<SLUG>_<ROLE>` at `resource_access.<slug>.roles`, two roles as the baseline, and a principal
with no recognised role refused rather than admitted. This ADR is what that costs in Grafana
specifically, and the three choices the platform decision deliberately leaves to a module.

Grafana's own model has three org roles — `Viewer`, `Editor`, `Admin` — plus a server-level
`GrafanaAdmin`, assignable from OIDC only when `allow_assign_grafana_admin` is set. Role
assignment is driven by `role_attribute_path`, a **JMESPath** expression evaluated against the
token and userinfo claims.

## Decision

The slug is `grafana`, so the roles are `GRAFANA_ADMIN` and `GRAFANA_VIEWER`, read from
`resource_access.grafana.roles`:

```ini
role_attribute_path   = contains(resource_access.grafana.roles[*], 'GRAFANA_ADMIN') && 'Admin' || contains(resource_access.grafana.roles[*], 'GRAFANA_VIEWER') && 'Viewer' || ''
role_attribute_strict = true
```

Three module-level choices on top of the platform decision:

- **`Editor` is not mapped.** Two roles, as ADR 013's baseline.
- **`allow_assign_grafana_admin` stays off**, so server administration is not something a claim
  can grant.
- **The local login form follows `oidc`.** `allow_local_login` defaults to `null`, meaning
  derive: on when `oidc` is `null`, off once an issuer is wired. Setting it `true` alongside
  `oidc` keeps a break-glass route; setting it `false` with no `oidc` is refused at plan time,
  because it admits nobody.

## Rationale

- **`role_attribute_strict = true` is how ADR 013's rule 2 is spelled in Grafana.** Without it,
  a token carrying no recognised role falls through to Grafana's default org role and the person
  is in. Strict turns absence into refusal, which is the whole point of the platform decision.
- **Server admin is not delegated.** `allow_assign_grafana_admin` would let a claim grant
  instance-wide administration across orgs. There is one org and one operator; the capability
  buys nothing and widens what a misconfigured issuer can do.
- **The expression is JMESPath, and this is worth writing down** because it is the most likely
  thing to be got wrong. A JSONPath-style `$.resource_access.grafana.roles` is syntactically
  accepted and matches nothing, which under strict mode refuses every login — a failure that
  looks like a broken issuer rather than a broken expression.
- **Closing the login form is what makes REQ-01 true rather than merely available.** Leaving it
  open means Grafana keeps a user list after all, which is the thing REQ-01 forbids.

## Consequences

- **Wiring `oidc` closes the local login form**, so when the issuer is down — and it likely runs
  in this same cluster — nobody can reach Grafana. `allow_local_login = true` is the deliberate
  exception, and it costs a static password living outside the OIDC path that nobody will
  rotate. Both states are defensible; neither is free, which is why it is an input rather than a
  decision made here on someone's behalf.
- **`allow_local_login` is the only derived default in the module.** Every other input means the
  same thing regardless of its neighbours. This one cannot: `false` is correct with an issuer and
  a lockout without one, so the safe value is a function of `oidc`, and a plan-time validation
  rejects the combination that admits nobody. OBS-13 asserts all four states.
- **The first sign-in after wiring `oidc` will fail** until the issuer emits
  `resource_access.grafana.roles`, and it will fail in a way that looks like this module's fault.
  That is ADR 013's consequence, inherited.
- Adding `Editor` later is a values change and a third clause in one expression. Nothing here
  forecloses it.
