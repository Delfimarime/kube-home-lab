# Platform specification

**Status:** draft ·
**Satisfies:** [REQ-05, REQ-06, REQ-08, REQ-09, REQ-10, REQ-12, REQ-13](requirements.md) ·
**Decisions:** [ADR 004](adr/004-scrape-config-via-prometheus-crds.md),
[ADR 005](adr/005-modules-are-applicationsets.md),
[ADR 007](adr/007-modules-receive-credentials.md),
[ADR 010](adr/010-resources-delivered-via-chart.md),
[ADR 011](adr/011-environments-are-clusters.md),
[ADR 012](adr/012-state-is-per-environment.md),
[ADR 013](adr/013-roles-are-carried-in-the-token.md),
[ADR 014](adr/014-exposed-does-not-mean-authorized.md),
[ADR 015](adr/015-units-are-wired-by-hand.md),
[ADR 016](adr/016-metrics-is-the-fourth-input.md),
[ADR 017](adr/017-stores-are-multi-tenant.md),
[ADR 018](adr/018-one-trust-bundle-for-the-cluster.md) ·
**Date:** 2026-08-05

This is the system: what the parts are, how they fit together, and which decision owns each
joint. What any one part *does* is in its own [spec](README.md#specifications); nothing here
repeats it.

## Intent

Provision workload-facing platform services — observability, identity, certificates and audit —
onto existing k3s clusters, in a way that is still understandable after six months of not being
touched.

The measure of success is not uptime. It is that a person returning to this repo can tell what
runs, why it was chosen, and what happens if they change it.

## Scope

**In scope.** Argo CD `ApplicationSet`/`Application` resources and their configuration, for:
observability (metrics, logs, traces), OIDC identity, certificate management, audit trail
management — per environment.

**Out of scope.** Cluster bootstrap. Argo CD itself. Traefik and the Gateway. PostgreSQL
([ADR 008](adr/008-postgresql-is-external.md)). Backup of any of it. Each is a per-environment
prerequisite this repo addresses and never creates.

**Secret storage and delivery is also out of scope, and that is the exclusion with teeth.**
A `secret_name` a module declares names a Secret somebody creates by hand, per environment, and
again after every rebuild — see [the open questions](requirements.md#open-questions). The one
exception is certificate material, which
[`certificate-management-cert-manager`](modules/certificate-management-cert-manager/README.md)
issues and a controller owns; nothing else here creates a Secret, and nothing here stores one.

## Assumptions

Each environment's cluster exists and already runs:

- **k3s** — a tiny cluster; one node, or a couple
- **Argo CD** — its own, not shared with another environment. This repo creates
  ApplicationSets; Argo CD installs and reconciles workloads
- **Gateway API (Traefik)** — a `Gateway` exists to attach `HTTPRoute`s to, with listeners open
  to routes from any namespace (`allowedRoutes.namespaces.from: All`). **Two listeners** are
  expected: one ordinary TLS, one demanding a client certificate — see
  [exposure and authorization](#exposure-and-authorization)
- **PostgreSQL** — reachable, with a database and credentials per consumer, described in that
  environment's `env.hcl`. Where it runs, and whether two environments share a server, is
  invisible to every module. OpenTofu's state lives in a PostgreSQL too
  ([ADR 012](adr/012-state-is-per-environment.md)) and is deliberately not assumed to be this
  one, or to be in this cluster

OpenTofu 1.9 or later ([ADR 019](adr/019-the-tool-is-opentofu.md)), because a variable
`validation` block references a second variable. The version is an OpenTofu version and does
not read across to Terraform.

If any of these is false, this repo does nothing useful for that environment, and it fails at
plan or sync time rather than degrading quietly.

## Domain model

Six nouns carry all the weight. Everything else is a detail of one of them.

```
  Requirement ──satisfied by──▶ Module ──renders──▶ ApplicationSet
                                  │                       │
                        provider  │  consumer             │ generates
                                  ▼                       ▼
                              Contract              Application ──owns──▶ every resource
                        (gateway/database/oidc)                          the chart needs

  Environment ──is──▶ one cluster ──runs──▶ its own Argo CD ──▶ the modules it ships
```

**Capability** — a job that needs doing: identity, observability, certificates, audit.
Capabilities are stable. What implements one is not.

**Module** — one implementation of one capability, named `<capability>-<implementation>`
(`openid-connect-keycloak`). The implementation half of the name is the swappable half, so a
module's outputs are named for the capability and never for the product: `issuer_url`, not
`keycloak_realm_id`. That naming rule is the whole mechanism behind REQ-09.

**Contract** — the three optional inputs every consumer module accepts, in one shape each. See
[contracts](#contracts).

**Provider and consumer** — a module is a *provider* of what it publishes and a *consumer* of
what it is wired to. A provider publishes its own address and knows nothing about who uses it; a
consumer receives a fully-formed reference to what it needs
([ADR 007](adr/007-modules-receive-credentials.md)). The relationship is one-directional on
purpose: adding a consumer is never a change to its provider.

**ApplicationSet and Application** — a module renders exactly one Argo CD `ApplicationSet` with
a `List` generator, one static entry per chart it needs, even at one entry
([ADR 005](adr/005-modules-are-applicationsets.md)). Each generated `Application` owns every
in-cluster resource its chart needs, and OpenTofu creates no bare Kubernetes object
([ADR 010](adr/010-resources-delivered-via-chart.md)) — so the Application is the unit of
ownership, and "reconciled by Argo CD" is true of everything without exception.

**Environment** — one Kubernetes cluster with its own Argo CD
([ADR 011](adr/011-environments-are-clusters.md)). Environments are configured independently and
do not interfere ([REQ-12](requirements.md)). An environment ships a module by having a
Terragrunt unit for it; there is no inventory file, so the tree cannot disagree with reality.

Worth being pedantic about the rest of the vocabulary: a **unit** is a Terragrunt directory, a
**module** is the OpenTofu it calls, and a **workload** is what ends up running in a pod. One
unit calls one module, which usually deploys more than one workload.

## Components

What an environment *may* ship — not what any particular one does. That is answered by listing
the environment's units ([ADR 011](adr/011-environments-are-clusters.md)).

| Module | Capability |
| --- | --- |
| [`certificate-management-cert-manager`](modules/certificate-management-cert-manager/README.md) | issues every certificate the environment uses, and distributes the root |
| [`openid-connect-keycloak`](modules/openid-connect-keycloak/README.md) | one OIDC issuer per environment |
| [`observability-storage-grafana-lgtm`](modules/observability-storage-grafana-lgtm/README.md) | collects and stores metrics, logs and traces |
| [`observability-console-grafana`](modules/observability-console-grafana/README.md) | reads whichever of them is switched on |
| [`audit-management-auditum`](modules/audit-management-auditum/README.md) | an audit record API — **blocked** |

**What each one provides and consumes is in its own spec**, and only there. This table names
the parts; the [mechanisms](#mechanisms) below describe how they meet.

Modules an environment ships are deployed into that environment's cluster only. Nothing here is
shared between environments.

## Mechanisms

Six behaviours span more than one module. Each is owned by exactly one decision, and this is the
list of them — a change to any is a change here first and in the modules second.

### Wiring

**Nothing is wired automatically** ([ADR 015](adr/015-units-are-wired-by-hand.md)). No unit
reads another unit's state; a value two units share — a hostname, a store address, a tenant
list, `metrics.enabled` — is declared once in `env.hcl` or `_envcommon/` and read from there by
both. There are no `dependency` blocks and no `mock_outputs`.

The consequence worth knowing: a hand-written value can disagree with what it describes, and
nothing detects it. Deriving both sides from one declaration is what keeps that narrow.

### Exposure and authorization

**`gateway` says a request can arrive, and nothing more**
([ADR 014](adr/014-exposed-does-not-mean-authorized.md)). A module authorizes where its workload
natively can — the console delegates to the issuer and refuses anyone carrying no role. Where
the workload cannot, that job belongs to the Gateway, which this repo does not provision.

**What changed, and it is the joint most likely to be misread:** this repo now provisions the
*material* for a Gateway to authorize with — a client authority and one shared client
certificate ([REQ-14](requirements.md)) — while still provisioning no Gateway. So an environment
may demand a client certificate on a listener, and whether it does is that environment's
configuration rather than this repo's. The OTLP ingest endpoint is the surface where this
matters, and `gateway.section_name` is the entire mechanism: pointing an endpoint at the mTLS
listener rather than the ordinary one is a call-site edit, with no module change either way.

The claim that holds regardless of listener: that surface is **write-only**, and no store is
ever routed.

### Identity and roles

**One issuer per environment, and what a person may do comes from the token**
([ADR 013](adr/013-roles-are-carried-in-the-token.md)). A consumer wired to `oidc` reads roles
named `<SLUG>_ADMIN` / `<SLUG>_VIEWER` from `resource_access.<slug>.roles`, maps them onto its
own native roles, and **refuses anyone carrying none**. `<slug>` is the OIDC client ID, not a
label chosen beside it. A workload that keeps its own permission list satisfies REQ-01 and still
fails [REQ-13](requirements.md).

The issuer publishes only its address. Clients, roles and grants are created by hand in its
console and are recorded nowhere — see [the open questions](#open-questions).

### Trust

**One bundle, in every namespace** ([ADR 018](adr/018-one-trust-bundle-for-the-cluster.md)).
Certificates come from an authority this repo owns, so a workload calling another over its
external hostname must trust the root or fail at the TLS handshake. The certificate module
distributes it; every consumer mounts it.

This is the first cross-module dependency here that is not an address, and it is load-bearing
for identity: a console with no bundle cannot complete an OIDC login, and the symptom looks like
a broken OIDC configuration rather than a trust problem.

### Telemetry and tenancy

**The stores are multi-tenant and the caller names its tenant**
([ADR 017](adr/017-stores-are-multi-tenant.md)). `X-Scope-OrgID` is mandatory on every read and
write, nothing validates it, and it is **not** a security boundary. What it buys is per-tenant
limits and retention, which is how [REQ-15](requirements.md) is met, and reads that can be
scoped.

Certificates and tenancy are deliberately unrelated: a client certificate says a caller may
write, the header says where. The environment's `tenants` value is read by the storage module
for limits and by the console for datasources, and passes between neither.

### Scraping

**A workload declares scraping through its own chart**
([ADR 004](adr/004-scrape-config-via-prometheus-crds.md)) — `serviceMonitor.enabled`, read
directly by the collector, never hand-written scrape config. It may only do so when the
environment has the CRDs and a collector, which is what `metrics.enabled` says
([ADR 016](adr/016-metrics-is-the-fourth-input.md)).

## Contracts

Every consumer module takes the same three optional inputs. Each defaults to `null`, and `null`
means "not wired" rather than "disabled by a flag" — absence of configuration, not a switch
someone has to remember to check.

| Variable | Meaning when set | Meaning when `null` |
| --- | --- | --- |
| `gateway` | emit a route for this workload | not exposed outside the cluster |
| `database` | connect to this PostgreSQL, credentials from a Secret | no database, or module fails if required |
| `oidc` | delegate authentication to this issuer | local authentication only |

**A fourth input crosses module boundaries and is not a contract**, because it carries a fact
about the environment rather than a reference to something addressable:

| Variable | Meaning when `true` | Meaning when `false` |
| --- | --- | --- |
| `metrics` | one field, `enabled`: the CRDs exist and a collector is reading them, so declare scraping | declare nothing; a `ServiceMonitor` would fail the sync or go unread |

Shapes are defined in [ADR 007](adr/007-modules-receive-credentials.md) and are not repeated
here. How a module turns `gateway` into resources is per-module — see
[ADR 010](adr/010-resources-delivered-via-chart.md).

Three rules follow, and hold across every module:

1. **A credential is passed by reference, never by value.** `secret_name` plus a key, never a
   password. No secret reaches a values.yaml, and therefore none reaches the rendered Helm
   values inside an `Application` spec in etcd.
2. **A provider publishes its address and nothing about its consumers.**
3. **A module declares what it needs, not when or by whom it is satisfied.** A `secret_name`
   that does not resolve yet is an operational state, not a spec violation. This is the same
   rule that lets `database` name a PostgreSQL this repo never provisions.

The two rules that used to sit here — roles come from the token, and exposure is not
authorization — are mechanisms rather than input conventions, and live above.

## Acceptance criteria

These five hold for every module in every environment. Module-specific criteria live in each
module's spec.

```gherkin
Feature: Platform provisioning

  @cluster
  Scenario: [PLAT-01] Argo CD owns every resource
    Given a module has been applied to an environment
    When its Deployments, StatefulSets, Services and HTTPRoutes are inspected
    Then each has an Argo CD Application among its owners
     And none of them is present in OpenTofu state

  @cluster
  Scenario: [PLAT-02] No secret value is written to the cluster in plaintext
    Given any module configured with a database or an OIDC client
    When its Argo CD Application spec is read from the API server
    Then no password, client secret or token appears in the rendered Helm values

  @cluster
  Scenario: [PLAT-03] Nothing is exposed by default
    Given a module applied with gateway set to null
    When HTTPRoutes in its namespace are listed
    Then none exist

  @cluster
  Scenario: [PLAT-04] A wired module is reachable
    Given a module applied with a gateway and hostname
    When that hostname is requested through the Gateway
    Then the workload responds

  @plan
  Scenario: [PLAT-05] An environment plans against its own cluster only
    Given two environments are configured
    When tofu plan runs for one of them
    Then every resource in the plan targets that environment's cluster
     And no resource belonging to the other appears in the plan
```

## Verification

Prose today, checked by hand. The route to executable, and what the tags mean, is in
[docs/README.md](README.md#making-the-criteria-executable).

Worth noting that four of the five are `@cluster`: what is being asserted is mostly ownership by
a controller OpenTofu never talks to. PLAT-05 is the exception and the one worth automating
first — it is checkable from a plan, and it is the criterion behind REQ-12.

## Open questions

Tracked in [requirements.md](requirements.md#open-questions), owned by the specs and ADRs that
would resolve them:

- **What is Auditum for?** — [audit-management-auditum](modules/audit-management-auditum/README.md)
- **What creates the Secrets every module references?** — nothing. See
  [requirements.md](requirements.md#open-questions)
- **What declares the realm?** — nothing. Clients, roles and grants exist only in the issuer's
  console, so [REQ-01](requirements.md) and [REQ-13](requirements.md) have no declared content
  anywhere in this repository, and a rebuild that loses the database loses the model with it.
  See [`openid-connect-keycloak`](modules/openid-connect-keycloak/README.md#open-items)
- **What backs up PostgreSQL?** — nothing. The environment's database holds the realm and every
  Grafana alert rule, neither of which is regenerable from git, and it is [out of scope](#scope)
  by [ADR 008](adr/008-postgresql-is-external.md). OpenTofu's state database is a separate
  concern and a separate instance ([ADR 012](adr/012-state-is-per-environment.md)); its contents
  *are* regenerable
