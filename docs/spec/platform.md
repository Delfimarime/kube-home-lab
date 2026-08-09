# Platform specification

**Status:** draft · **Date:** 2026-08-05

## Intent

Provision workload-facing platform services — observability, identity, secrets and audit —
onto an existing k3s homelab, in a way that is still understandable after six months of not
being touched.

The measure of success is not uptime. It is that a person returning to this repo can tell
what runs, why it was chosen, and what happens if they change it.

## Scope

**In scope.** Argo CD `Application` resources and their configuration, for: observability
(metrics, logs, traces), OIDC identity, secret storage and delivery, audit trail management.

**Out of scope.** Cluster bootstrap. Argo CD itself. Traefik and the Gateway. PostgreSQL
([ADR 8](../adr/0008-postgresql-is-external.md)). Backup of anything above.

## Assumptions

The cluster exists and already runs:

- **k3s** — one node, or a couple
- **Argo CD** — this repo creates Applications; Argo CD installs and reconciles workloads
- **Gateway API (Traefik)** — a `Gateway` exists to attach `HTTPRoute`s to
- **PostgreSQL** — reachable, with a database and credentials per consumer

Terraform 1.9 or later, because variable `validation` blocks reference other variables.

## Shared contracts

Every consumer module takes the same three optional inputs. Each defaults to `null`, and
`null` means "not wired" rather than "disabled by a flag".

| Variable | Meaning when set | Meaning when `null` |
| --- | --- | --- |
| `gateway` | emit an `HTTPRoute` for this workload's UI | not exposed outside the cluster |
| `database` | connect to this PostgreSQL, credentials from a Secret | no database, or module fails if required |
| `oidc` | delegate authentication to this issuer | local authentication only |

Shapes are defined in [ADR 6](../adr/0006-shared-gateway-input.md) and
[ADR 7](../adr/0007-modules-receive-credentials.md). How a module actually turns `gateway`
into resources is a separate, per-module decision — see
[ADR 10](../adr/0010-resources-delivered-via-chart.md).

Two rules follow from those ADRs and hold across every module:

1. **A credential is passed by reference, never by value.** `secret_name` plus a key, never
   a password. No secret reaches a values.yaml, and therefore none reaches the rendered Helm
   values inside an `Application` spec in etcd.
2. **A provider module publishes its address and nothing about its consumers.**

## Modules

| Module | Provides | Consumes |
| --- | --- | --- |
| `secret-manager-openbao` | OpenBao + External Secrets Operator | — |
| `openid-connect-zitadel` | `issuer_url`, `discovery_url` | `database`, `gateway` |
| `observability-victoria-metrics` | metrics / logs / traces endpoints, Grafana | `gateway`, `oidc` |
| `audit-management-auditum` | audit record API | `database`, `gateway` |

Bootstrap order: secrets, then identity, then the rest.

## Acceptance criteria

```gherkin
Feature: Platform provisioning

  Scenario: Argo CD owns every resource
    Given a module has been applied
    When its resources are inspected
    Then every Deployment, StatefulSet, Service and HTTPRoute
     And has an Argo CD Application as its owner
     And no resource was created directly by Terraform

  Scenario: No secret value is written to the cluster in plaintext
    Given any module configured with a database or an OIDC client
    When its Argo CD Application spec is read from the API server
    Then no password, client secret or token appears in the rendered Helm values

  Scenario: Nothing is exposed by default
    Given a module applied with gateway set to null
    When HTTPRoutes in its namespace are listed
    Then none exist

  Scenario: A wired module is reachable
    Given a module applied with a gateway and hostname
    When that hostname is requested through the Gateway
    Then the workload's UI responds
```

## Verification

These criteria are prose today, checked by hand. Making them executable means asserting
against `terraform plan -json` with a policy tool such as conftest for the structural ones,
and `kubectl` assertions for the runtime ones. That harness does not exist yet and is not
worth building before the modules do.

## Open questions

- **What is Auditum for?** Application audit trails, or Kubernetes API audit logs? These are
  different systems and only one of them is Auditum. Unresolved — see
  [audit-management-auditum](modules/audit-management-auditum.md).
- **How does OpenBao unseal?** Deliberate choice required; see
  [ADR 9](../adr/0009-secret-delivery-openbao-eso.md).
