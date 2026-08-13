# Platform specification

**Status:** draft · **Satisfies:** [REQ-05, REQ-06, REQ-08, REQ-09, REQ-10, REQ-12, REQ-13](requirements.md) ·
**Decisions:** [ADR 005](adr/005-modules-are-applicationsets.md),
[ADR 007](adr/007-modules-receive-credentials.md),
[ADR 010](adr/010-resources-delivered-via-chart.md),
[ADR 011](adr/011-environments-are-clusters.md),
[ADR 012](adr/012-state-is-per-environment.md) · **Date:** 2026-08-05

## Intent

Provision workload-facing platform services — observability, identity and audit — onto
existing k3s clusters, in a way that is still understandable after six months of not being
touched.

The measure of success is not uptime. It is that a person returning to this repo can tell
what runs, why it was chosen, and what happens if they change it.

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

**Capability** — a job that needs doing: identity, observability, secret management, audit.
Capabilities are stable. What implements one is not.

**Module** — one implementation of one capability, named `<capability>-<implementation>`
(`openid-connect-zitadel`). The implementation half of the name is the swappable half, so a
module's outputs are named for the capability and never for the product: `issuer_url`, not
`zitadel_org_id`. That naming rule is the whole mechanism behind REQ-09.

**Contract** — the three optional inputs every consumer module accepts, in one shape each.
See [shared contracts](#shared-contracts).

**Provider and consumer** — a module is a *provider* of what it publishes and a *consumer* of
what it is wired to. A provider publishes its own address and knows nothing about who uses
it; a consumer receives a fully-formed reference to what it needs
([ADR 007](adr/007-modules-receive-credentials.md)). The relationship is one-directional on
purpose: adding a consumer is never a change to its provider.

**ApplicationSet and Application** — a module renders exactly one Argo CD `ApplicationSet`
with a `List` generator, one static entry per chart it needs, even at one entry
([ADR 005](adr/005-modules-are-applicationsets.md)). Each generated `Application` owns every
in-cluster resource its chart needs. Terraform creates no bare Kubernetes object
([ADR 010](adr/010-resources-delivered-via-chart.md)) — so the Application is the unit of
ownership, and "reconciled by Argo CD" is true of everything without exception.

**Environment** — one Kubernetes cluster with its own Argo CD
([ADR 011](adr/011-environments-are-clusters.md)). Environments are configured independently
and do not interfere ([REQ-12](requirements.md)). An environment ships a module by having a
Terragrunt unit for it; there is no inventory file, so the tree cannot disagree with reality.

Worth being pedantic about the rest of the vocabulary: a **unit** is a Terragrunt directory,
a **module** is the Terraform it calls, and a **workload** is what ends up running in a pod.
One unit calls one module, which usually deploys more than one workload.

## Scope

**In scope.** Argo CD `ApplicationSet`/`Application` resources and their configuration, for:
observability (metrics, logs, traces), OIDC identity, audit trail management — per
environment.

**Out of scope.** Cluster bootstrap. Argo CD itself. Traefik and the Gateway. PostgreSQL
([ADR 008](adr/008-postgresql-is-external.md)). Backup of anything above. All of these are now
per-environment prerequisites rather than single ones.

**Secret storage and delivery is also out of scope, and that is the exclusion with teeth.**
Every `secret_name` a module declares names a Secret somebody creates by hand, per environment,
and again after every rebuild. See [the open questions](requirements.md#open-questions).

## Assumptions

Each environment's cluster exists and already runs:

- **k3s** — a tiny cluster; one node, or a couple
- **Argo CD** — its own, not shared with another environment. This repo creates
  ApplicationSets; Argo CD installs and reconciles workloads
- **Gateway API (Traefik)** — a `Gateway` exists to attach `HTTPRoute`s to, with listeners
  open to routes from any namespace (`allowedRoutes.namespaces.from: All`). No module
  provisions a `ReferenceGrant`; this assumption is why none is needed
- **PostgreSQL** — reachable, with a database and credentials per consumer. Described in that
  environment's `env.hcl`. Where it runs, and whether two environments happen to share a
  server, is invisible to every module

Terraform 1.9 or later, because variable `validation` blocks reference other variables.

If any of these is false, this repo does nothing useful for that environment, and it fails at
plan or sync time rather than degrading quietly.

## Shared contracts

Every consumer module takes the same three optional inputs. Each defaults to `null`, and
`null` means "not wired" rather than "disabled by a flag" — absence of configuration, not a
switch someone has to remember to check.

| Variable | Meaning when set | Meaning when `null` |
| --- | --- | --- |
| `gateway` | emit an `HTTPRoute` for this workload's UI | not exposed outside the cluster |
| `database` | connect to this PostgreSQL, credentials from a Secret | no database, or module fails if required |
| `oidc` | delegate authentication to this issuer | local authentication only |

Shapes are defined in [ADR 007](adr/007-modules-receive-credentials.md). How a module turns
`gateway` into resources is a separate, per-module decision — see
[ADR 010](adr/010-resources-delivered-via-chart.md).

Three rules follow, and hold across every module:

1. **A credential is passed by reference, never by value.** `secret_name` plus a key, never
   a password. No secret reaches a values.yaml, and therefore none reaches the rendered Helm
   values inside an `Application` spec in etcd.
2. **A provider module publishes its address and nothing about its consumers.**
3. **A module declares what it needs, not when or by whom it is satisfied.** A `secret_name`
   that does not resolve yet is an operational state, not a spec violation. This is the same
   rule that lets `database` name a PostgreSQL this repo never provisions.
4. **What a person may do comes from the token, not the workload.** A consumer wired to `oidc`
   reads roles named `<SLUG>_ADMIN` / `<SLUG>_VIEWER` from `resource_access.<slug>.roles`, maps
   them onto its own native roles, and refuses anyone carrying none
   ([ADR 013](adr/013-roles-are-carried-in-the-token.md)). A workload that keeps its own
   permission list satisfies REQ-01 and still fails [REQ-13](requirements.md).

## Module catalogue

What an environment *may* ship — not what any particular one does. That is answered by
listing the environment's units ([ADR 011](adr/011-environments-are-clusters.md)).

| Module | Provides | Consumes |
| --- | --- | --- |
| [`openid-connect-zitadel`](modules/openid-connect-zitadel/README.md) | `issuer_url`, `discovery_url` | `database`, `gateway` |
| [`observability-grafana-lgtm`](modules/observability-grafana-lgtm/README.md) | OTLP ingest endpoint, Grafana | `gateway`, `oidc`, `database` |
| [`audit-management-auditum`](modules/audit-management-auditum/README.md) | audit record API | `database`, `gateway` |

Modules an environment ships are deployed into that environment's cluster only. Nothing here
is shared between environments.

## Acceptance criteria

These four hold for every module in every environment. Module-specific criteria live in each
module's spec.

```gherkin
Feature: Platform provisioning

  @cluster
  Scenario: [PLAT-01] Argo CD owns every resource
    Given a module has been applied to an environment
    When its Deployments, StatefulSets, Services and HTTPRoutes are inspected
    Then each has an Argo CD Application among its owners
     And none of them is present in Terraform state

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
    Then the workload's UI responds

  @plan
  Scenario: [PLAT-05] An environment plans against its own cluster only
    Given two environments are configured
    When terraform plan runs for one of them
    Then every resource in the plan targets that environment's cluster
     And no resource belonging to the other appears in the plan
```

## Verification

Prose today, checked by hand. The route to executable, and what the tags mean, is in
[docs/README.md](README.md#making-the-criteria-executable).

Worth noting that four of the five are `@cluster`: what is being asserted is mostly ownership
by a controller Terraform never talks to. PLAT-05 is the exception and the one worth
automating first — it is checkable from a plan, and it is the criterion behind REQ-12.

## Open questions

Tracked in [requirements.md](requirements.md#open-questions), owned by the specs and ADRs
that would resolve them:

- **What is Auditum for?** — [audit-management-auditum](modules/audit-management-auditum/README.md)
- **What creates the Secrets every module references?** — nothing, today. See
  [requirements.md](requirements.md#open-questions)
- **Which state backend?** — [ADR 012](adr/012-state-is-per-environment.md)
