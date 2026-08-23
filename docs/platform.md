# Platform specification

**Status:** implemented ·
**Satisfies:** [REQ-05, REQ-06, REQ-08, REQ-09, REQ-10, REQ-12, REQ-13](requirements.md) ·
**Decisions:** [ADR 004](adr/004-scrape-config-via-prometheus-crds.md),
[ADR 005](adr/005-modules-are-applicationsets.md),
[ADR 007](adr/007-modules-receive-credentials.md),
[ADR 010](adr/010-resources-delivered-via-chart.md),
[ADR 011](adr/011-environments-are-clusters.md),
[ADR 012](adr/012-state-is-per-environment.md),
[ADR 013](adr/013-roles-are-carried-in-the-token.md),
[ADR 014](adr/014-exposed-does-not-mean-authorized.md),
[ADR 016](adr/016-metrics-is-the-fourth-input.md),
[ADR 017](adr/017-stores-are-multi-tenant.md),
[ADR 018](adr/018-one-trust-bundle-for-the-cluster.md),
[ADR 020](adr/020-one-root-module.md),
[ADR 026](adr/026-roles-decide-the-operation-relationships-decide-the-resource.md),
[ADR 027](adr/027-a-machine-caller-is-authorized-by-scope.md) ·
**Date:** 2026-08-05

This is the system: what the parts are, how they fit together, and which decision owns each
joint. What any one part *does* is in its own [spec](README.md#specifications); nothing here
repeats it.

## Intent

Provision workload-facing platform services — observability, identity, authorization, certificates
and the object storage behind them — onto existing k3s clusters, in a way that is still
understandable after six months of not being touched.

The measure of success is not uptime. It is that a person returning to this repo can tell what
runs, why it was chosen, and what happens if they change it.

## Scope

**In scope.** Argo CD `ApplicationSet`/`Application` resources and their configuration, for:
observability (metrics, logs, traces), OIDC identity, resource-level authorization, certificate
management, and the object storage those workloads keep their data in — per environment.

**Object storage is in scope where PostgreSQL is not**, and the line is not size. A database is
something an environment already has, administered and older than this repository
([ADR 008](adr/008-postgresql-is-external.md)); an S3 endpoint is not, and no environment here
would grow one for its own sake. What a cluster plausibly already runs is the test, and object
storage falls on the other side of it.

**Out of scope.** Cluster bootstrap. Argo CD itself. Traefik and the Gateway. PostgreSQL
([ADR 008](adr/008-postgresql-is-external.md)). Backup of any of it. Each is a per-environment
prerequisite this repo addresses and never creates.

**Secret storage is also out of scope, and that is the exclusion with teeth.** The *object* is
now declared: a module given no name for a credential renders the Secret itself, keys present and
values empty, and Argo CD is told not to touch the contents again
([ADR 022](adr/022-secrets-are-rendered-empty.md)) — while an environment that has something else
creating Secrets names them and is left alone. The *value* is typed in by a person, per
environment and again after every rebuild, stored nowhere and rotated by nothing — see
[the open questions](requirements.md#open-questions). The one exception is certificate material,
which [`certificate-management-cert-manager`](modules/certificate-management-cert-manager/README.md)
issues and a controller owns, values and all.

## Assumptions

Each environment's cluster exists and already runs:

- **k3s** — a tiny cluster; one node, or a couple
- **Argo CD** — its own, not shared with another environment. This repo creates
  ApplicationSets; Argo CD installs and reconciles workloads
- **Gateway API (Traefik)** — a `Gateway` exists to attach `HTTPRoute`s to, with listeners open
  to routes from any namespace (`allowedRoutes.namespaces.from: All`). **Two listeners** are
  expected: one ordinary TLS, one demanding a client certificate — see
  [exposure](#exposure-gateway-in-a-route-out)
- **PostgreSQL** — reachable, with a database and credentials per consumer, described in that
  environment's var file. Where it runs, and whether two environments share a server, is
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

**Capability** — a job that needs doing: identity, authorization, observability, certificates,
object storage. Capabilities are stable. What implements one is not.

**Module** — one implementation of one capability, named `<capability>-<implementation>`
(`openid-connect-keycloak`). The implementation half of the name is the swappable half, so a
module's outputs are named for the capability and never for the product: `issuer_url`, not
`keycloak_realm_id`. That naming rule is the whole mechanism behind REQ-09.

**Contract** — one of three inputs a consumer module accepts when it needs it, each in a fixed
shape. A module takes the contracts it uses and no others, so the shape is what is shared and the
set is not. See [contracts](#contracts).

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
do not interfere ([REQ-12](requirements.md)) — as far as the operator's shell carries that, which
is where the guarantee now lives ([ADR 020](adr/020-one-root-module.md)). An environment ships a
module by having a `module` block for it; there is no inventory file, so the composition cannot
disagree with reality.

Worth being pedantic about the rest of the vocabulary: the **root module** is the composition at
the repository root, a **module** is one of the things it calls, and a **workload** is what ends
up running in a pod. One module usually deploys more than one workload.

## Components

What an environment *may* ship — not what any particular one does. That is answered by listing
the root module's `module` blocks ([ADR 011](adr/011-environments-are-clusters.md)).

| Module | Capability |
| --- | --- |
| [`certificate-management-cert-manager`](modules/certificate-management-cert-manager/README.md) | issues every certificate the environment uses, and distributes the root |
| [`openid-connect-keycloak`](modules/openid-connect-keycloak/README.md) | one OIDC issuer per environment |
| [`object-storage-rustfs`](modules/object-storage-rustfs/README.md) | one S3-compatible endpoint the stores write into |
| [`observability-storage-grafana-lgtm`](modules/observability-storage-grafana-lgtm/README.md) | collects and stores metrics, logs and traces |
| [`observability-console-grafana`](modules/observability-console-grafana/README.md) | reads whichever of them is switched on |
| [`resource-authorization-ory-keto`](modules/resource-authorization-ory-keto/README.md) | answers whether a subject may act on a particular resource |
| [`access-proxy-ory-oathkeeper`](modules/access-proxy-ory-oathkeeper/README.md) | authenticates a request before it reaches a workload that cannot |

**What each one provides and consumes is in its own spec**, and only there. This table names
the parts; the [joints](#joints) below describe where they meet.

Modules an environment ships are deployed into that environment's cluster only. Nothing here is
shared between environments.

## Joints

Seven places where modules meet. **Each names the value that passes and the decision that owns
it**; the rule is in the [CONSTITUTION](../CONSTITUTION.md) and the argument is in the ADR, and
neither is repeated here. What this section is for is the thing neither of those holds — which
module hands what to which, and what breaks at the seam.

### Wiring — how any value crosses a boundary

Three kinds, and which one a value is decides whether it can ever disagree with itself:

| Kind | Written | Can drift? |
| --- | --- | --- |
| `module.<a>.<output>` → `module.<b>` | nowhere — resolved at plan time | no |
| a root variable read by several modules | once, in the environment's var file | across environments only |
| derived at the root from another input | nowhere | no |

The third is the shape to prefer where it exists. `metrics.enabled` is the worked example: no
environment declares it, because whether the cluster has scrape CRDs and a collector follows from
whether it ships a metrics store ([ADR 024](adr/024-the-metrics-fact-is-derived.md), §4.2, §4.5).

### Exposure — `gateway` in, a route out

`gateway` carries a hostname and a listener reference; the module renders an `HTTPRoute` and
nothing else. **The joint most likely to be misread** is that this repo provisions the *material*
a Gateway authorizes with — a client authority and a shared client certificate
([REQ-14](requirements.md)) — and provisions no Gateway. `gateway.section_name` is the whole of
the mechanism: pointing a surface at the mTLS listener rather than the ordinary one is a
call-site edit, and no module changes either way
([ADR 014](adr/014-exposed-does-not-mean-authorized.md), §6.4).

Holds regardless of listener: the OTLP ingest surface is write-only, and no store is ever routed.

### Identity — an issuer address in, a refusal or a native role out

`openid-connect-keycloak` publishes `issuer_url`; a consumer's `oidc` input carries it, a client
id and a Secret reference. What crosses is an address and a claim path — never a user list, never
a role list ([ADR 013](adr/013-roles-are-carried-in-the-token.md), §6.1, §6.2).

`<slug>` and `oidc.client_id` are two inputs holding one value and **nothing compares them**; a
mismatch is indistinguishable from a person with no role. The clients, roles and grants
themselves exist only in the issuer's console — see [the open questions](#open-questions).

### Authorization — a store address in, a per-resource answer out

Roles decide whether a person may perform an operation; relationships decide whether they may
perform it on a particular resource
([ADR 026](adr/026-roles-decide-the-operation-relationships-decide-the-resource.md)). The two are
`AND`, never a fallback for one another.

What crosses this joint is an address —
[`resource-authorization-ory-keto`](modules/resource-authorization-ory-keto/README.md) publishes a
read URL and a write URL, and they are different trust levels rather than one address with a
credential. The write URL goes to
[`access-proxy-ory-oathkeeper`](modules/access-proxy-ory-oathkeeper/README.md) as an upstream, and
the proxy's pod selector goes back the other way as the store's `write_access_from`. **That
selector is the only two-way joint here**, and each half understates the protection when read
alone.

Machine callers are authorized by scope and audience rather than by role
([ADR 027](adr/027-a-machine-caller-is-authorized-by-scope.md)), so this is the one place two
authorization vocabularies meet. The principal is the tell.

### Trust — one bundle, mounted everywhere

`certificate-management-cert-manager` publishes `trust_bundle_name`; every consumer mounts that
ConfigMap ([ADR 018](adr/018-one-trust-bundle-for-the-cluster.md), §7.2).

**The only cross-module dependency here that is not an address**, and it is load-bearing for
identity: a console with no bundle cannot complete an OIDC login, and the symptom reads as a
broken OIDC configuration rather than a trust problem.

### Tenancy — a header on a write, a label on a workload

`X-Scope-OrgID` crosses from caller to store on every read and write, and **nothing validates
it** ([ADR 017](adr/017-stores-are-multi-tenant.md), §8.2). A scraped workload has no request to
put it in, so it carries `opentelemetry.io/tenant` on its Service and its pods and the collector
copies it ([ADR 025](adr/025-a-workload-carries-its-tenant.md)).

The environment's `tenants` value reaches the storage module for limits and the console for
datasources, and passes between neither — which is why the console reads the storage module's
`reserved_tenants` rather than restating them.

Certificates and tenancy are deliberately unrelated: a client certificate says a caller may
write, the header says where.

### Scraping — a chart flag in, a series out

A workload declares scraping through its own chart's `serviceMonitor.enabled` and nothing else
([ADR 004](adr/004-scrape-config-via-prometheus-crds.md), §8.1). `metrics.enabled` is what says
it may — the CRDs and the collector ship with a metrics store and with nothing else, so the root
derives it ([ADR 024](adr/024-the-metrics-fact-is-derived.md)).

`initial_deployment` holds every `ServiceMonitor` back for the one apply that installs the CRDs,
and is unset again after it. That ordering is the seam: a `ServiceMonitor` applied before its CRD
fails the sync rather than waiting.

## Contracts

Every consumer module takes the same three optional inputs. Each defaults to `null`, and `null`
means "not wired" rather than "disabled by a flag" — absence of configuration, not a switch
someone has to remember to check.

| Variable | Meaning when set | Meaning when `null` |
| --- | --- | --- |
| `gateway` | emit a route for this workload | not exposed outside the cluster |
| `services` | *(instead of `gateway`, where a module serves several surfaces)* one entry per surface: its `port`, its `hostname`, its Gateway | a surface with no hostname is not exposed |
| `database` | connect to this PostgreSQL, credentials from a Secret | no database, or module fails if required |
| `oidc` | delegate authentication to this issuer | local authentication only |

**A fourth input crosses module boundaries and is not a contract**, because it carries a fact
about the environment rather than a reference to something addressable:

| Variable | Meaning when `true` | Meaning when `false` |
| --- | --- | --- |
| `metrics` | `enabled`: the CRDs exist and a collector is reading them, so declare scraping | declare nothing; a `ServiceMonitor` would fail the sync or go unread |

A module takes it and is told; nobody writes it down. The root module derives it from the metrics
store ([ADR 024](adr/024-the-metrics-fact-is-derived.md)), which is what installs the CRDs and
runs the collector.

It carries a second field. **`metrics.tenant` is which tenant this workload's telemetry is stored
under**, written by the module onto its Service and its pods as `opentelemetry.io/tenant`, where the
collector discovers it and routes the write ([ADR 025](adr/025-a-workload-carries-its-tenant.md)).
`null` leaves both unlabelled, which stores it as the cluster's own — the ordinary case, since every
module here deploys platform infrastructure.

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

Two rules that used to sit here — roles come from the token, and exposure is not authorization —
are joints rather than input conventions, and live above.

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
