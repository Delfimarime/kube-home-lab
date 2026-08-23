# LOCAL-001. Applying the role convention to Grafana

**Status:** accepted · **Scope:** module — `observability-console-grafana` ·
**Date:** 2026-08-12 ·
revised 2026-08-16 (the login form is derived, not an input; the admin credential is a Secret an
operator fills)

**Grafana maps `GRAFANA_ADMIN` and `GRAFANA_VIEWER` from the token and admits nobody carrying
neither.**

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
- **The local login form follows `oidc`, and no input governs it.** On when `oidc` is `null`,
  off once an issuer is wired. An earlier draft made this an input, `allow_local_login`,
  defaulting to `null` meaning derive; it was removed because three of its four states restated
  the derived one and the fourth admitted nobody and had to be refused at plan time. A knob whose
  only novel setting is invalid is not a knob.

## Context

[ADR 013](../../../adr/013-roles-are-carried-in-the-token.md) settles the shape:
`<SLUG>_<ROLE>` at `resource_access.<slug>.roles`, two roles as the baseline, and a principal
with no recognised role refused rather than admitted. This ADR is what that costs in Grafana
specifically, and the three choices the platform decision deliberately leaves to a module.

Grafana's own model has three org roles — `Viewer`, `Editor`, `Admin` — plus a server-level
`GrafanaAdmin`, assignable from OIDC only when `allow_assign_grafana_admin` is set. Role
assignment is driven by `role_attribute_path`, a **JMESPath** expression evaluated against the
token and userinfo claims.

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

## Alternatives

- **Map to `Editor` as well.** Grafana has three org roles and this uses two. A third would be a
  name for a person who does not exist here, and
  [ADR 013](../../../adr/013-roles-are-carried-in-the-token.md) sets two as the baseline.
- **Assign `GrafanaAdmin` from the token**, with `allow_assign_grafana_admin`. It hands
  server-level control to whatever the issuer says, and the break-glass admin account exists
  precisely for when the issuer is what is broken.
- **Leave `role_attribute_strict` off**, so a principal with no recognised role falls through to
  Grafana's default. That is exactly the comfortable default
  [ADR 013](../../../adr/013-roles-are-carried-in-the-token.md)'s rule 2 refuses.

## Consequences

- **Wiring `oidc` closes the local login form**, so when the issuer is down — and it likely runs
  in this same cluster — nobody can reach Grafana through a browser. What remains is the admin
  account authenticating to the HTTP API with basic auth: unadvertised rather than absent, and
  worth knowing before an outage rather than during one. Its credential is a Secret an operator
  fills like any other, because the alternative is the chart inventing one on every render.
- **Two roles is the whole of what a claim can grant here.** Nothing in this module maps a claim
  to server administration, and the admin account is reached by a route no token touches. The two
  are deliberately unrelated: one is what a person signs in as, the other is what you use when
  signing in is impossible.
- **The first sign-in after wiring `oidc` will fail** until the issuer emits
  `resource_access.grafana.roles`, and it will fail in a way that looks like this module's fault.
  That is ADR 013's consequence, inherited.
- Adding `Editor` later is a values change and a third clause in one expression. Nothing here
  forecloses it.
