# AGENTS.md

Guidance for AI coding agents (Claude Code, Codex, etc.) working in this repository.

**Read [CONSTITUTION.md](CONSTITUTION.md) first.** It holds every rule an implementer must not
break, each citing the decision behind it. This file is orientation and current state only — the
rules are not repeated here.

## Where things are documented

| For | Read |
| --- | --- |
| The rules, and what breaks if you ignore one | [CONSTITUTION.md](CONSTITUTION.md) |
| What has to be true, and why | [docs/requirements.md](docs/requirements.md) |
| The domain model, contracts, and behaviour spanning modules | [docs/platform.md](docs/platform.md#mechanisms) |
| A specific module | `docs/modules/<module>/README.md` and its `adr/` |
| Why a platform-wide choice was made | [docs/adr/](docs/README.md#decisions) |
| Doc conventions, ID schemes, statuses | [docs/README.md](docs/README.md#conventions) |
| How to run anything | [README.md](README.md#running-it) |

## Repository structure

```
CONSTITUTION.md                the rules
main.tf                        required_version, required_providers, provider, backend
variables.tf                   everything true of the cluster being addressed
<capability>.tf                one module block per capability this cluster ships
outputs.tf
modules/<capability>-<impl>/
  *.tf                         the OpenTofu that renders this module's ApplicationSet
  helm/<chart>/                a chart this repo authors, when no upstream one fits
modules/secret-template/       the one directory here that is not a capability: other
                               modules import it, it renders nothing, and it returns the
                               element that puts an empty Secret in their ApplicationSet
docs/                          requirements, specs, decisions
```

## Before you change anything

1. **Read [CONSTITUTION.md](CONSTITUTION.md).** Most mistakes here are a rule in it, already
   written down with its reasoning.
2. **Read the module's `README.md` and every ADR it links** — its own `LOCAL-` ones and the
   platform ADRs it obeys (§10.6).
3. **Specs before code** (§10.2). A new decision needs the scope test in §10.4, and the tell in
   §10.5 is worth checking before you write it in the wrong place.
4. **Don't cite a document from code** (§10.3). Write the reason into the comment instead.

## Blocked and undecided

Live state, not rules. Each of these is a reason to stop and ask rather than proceed.

- **Audit record management is out of scope, and the requirement behind it is retired.** REQ-07
  and the `audit-management-auditum` spec were both dropped on 2026-08-23: nothing here writes an
  audit record, and the requirement never resolved into a single subject — application audit
  trails and Kubernetes API audit logs are different systems. Don't reinstate either. An
  application that later needs an audit trail gets a new requirement written against it, not this
  one revived ([requirements.md](docs/requirements.md)).
- **The identity model is not declared anywhere, and this is the largest gap in the platform.**
  Keycloak's realm — clients, redirect URIs, the `<SLUG>_<ROLE>` roles, every grant — is created
  by hand in a console. **This was surveyed on 2026-08-22 and the gap was left open on purpose**:
  no mechanism that exists reconciles a realm, and the one CRD that reconciles anything covers
  clients without roles, on an experimental API, behind a server feature flag. The survey, the
  four candidates and the conditions worth revisiting it under are in
  [the module's Open items](docs/modules/openid-connect-keycloak/README.md#open-items) — read
  them before proposing this again, because the obvious answer has already been costed. Don't
  paper over it with a module input carrying a role list (§6.3).
- **Nothing backs up PostgreSQL**, and two things in it cannot be regenerated from git: Keycloak's
  realm and every Grafana alert rule. Don't add a third without saying so. OpenTofu state is in a
  PostgreSQL too, but a separate one, and it *is* regenerable
  ([ADR 012](docs/adr/012-state-is-per-environment.md)).
- **The object store is pre-1.0, and nothing creates its buckets.** `object-storage-rustfs` pins
  a chart whose appVersion is `1.0.0-beta.12`, and every stored signal now lives behind it. The
  buckets each store writes to are created by hand, per environment; a missing one is not a sync
  failure — every store comes up healthy and fails on its first write. Don't add a bucket input
  to a module that cannot create one.
- **Three things are unverified, and each would change a spec.** Check before implementing, not
  after:
  - whether Alloy's `otelcol.auth.headers` accepts `from_context` and `default_value` at the
    pinned version — the chart wiring for [ADR 017](docs/adr/017-stores-are-multi-tenant.md) is
    confirmed by rendering, the component is not;
  - whether Traefik supports `tls.frontendValidation` on a listener — decides whether mTLS is
    portable Gateway API or a Traefik `TLSOption`;
  - whether Loki's and Tempo's charts expose per-tenant overrides — decides the shape
    `mimir-monolithic` is written to match.
