# Requirements

**Status:** accepted · **Date:** 2026-08-09

What has to be true of this platform. Not how — the how is [the specs](platform.md), and the
why-this-way is [the ADRs](README.md#decisions).

A requirement here is a statement that a completely different implementation could also
satisfy. If it names a product, it is a decision and belongs in an ADR.

## The problem

A small number of environments, each its own tiny k3s cluster with its own Argo CD, and one
operator across all of them. Stretches of weeks where nobody touches any of them.

Every workload arrives with its own login, its own storage assumption and its own idea of how
to be exposed. Left alone, that becomes a set of clusters nobody can safely change, because
nobody remembers what any of them does — or which of them is different, and why.

## The requirements

| ID | Requirement | Because |
| --- | --- | --- |
| REQ-01 | Within an environment, a person signs in to its services with one account. Workloads do not keep their own user lists. | Per-service logins are the first thing to rot, and the last thing anyone audits. |
| REQ-02 | Metrics, logs and traces are each present or absent independently. None is a precondition for another. | An environment wants one of them long before it wants three, and paying for the other two meanwhile is the whole cost problem. |
| REQ-03 | Whatever observability is switched on is queried from one place. | Two query UIs is one more than a single operator will keep in their head. |
| REQ-04 | Credentials survive a cluster rebuild, and none is committed to this repository. | A rebuild is routine here. Losing every credential to one should not be. |
| REQ-05 | No credential is readable from the API server as part of a workload's configuration. | Anything in a `values.yaml` ends up rendered into an object in etcd in plaintext. |
| REQ-06 | A workload is unreachable from outside its cluster unless it has been deliberately exposed. | Exposure should be an act, not the default that nobody noticed. |
| REQ-07 | Applications have somewhere to write audit records that survives a restart and can be queried. | *Blocked — see [the open questions](#open-questions).* |
| REQ-08 | Every in-cluster resource is reconciled from a declared source. Nothing is applied by hand; nothing drifts silently. | The point of the whole exercise is that a cluster matches something readable. |
| REQ-09 | Replacing the product behind a capability does not change what consumes it. | Every choice below was made once, on partial information, and at least one will turn out wrong. |
| REQ-10 | Standing resource cost stays proportionate to a tiny k3s cluster, per environment. An environment does not pay for capability it does not ship. | RAM is the real budget, spent all day, every day, and now spent once per environment. |
| REQ-11 | Six months later, a maintainer can find out what runs, why it was chosen, and what breaks if they change it. | This is the actual measure of success. Uptime is not. |
| REQ-12 | Environments do not interfere with one another. Each is configured independently. | A change or an outage in one must not be visible in another — otherwise there is one environment wearing several names. |

**REQ-12's boundary.** It covers everything this repo provisions: separate clusters, separate
Argo CDs, separate state. It does not cover shared external dependencies — one PostgreSQL
server hosting databases for two environments still couples them, and nothing here prevents
that. Modules are correctly indifferent
([ADR 007](adr/007-modules-receive-credentials.md)); the requirement is simply not claiming
more than it delivers.

## Traceability

Each requirement, the decisions that resolve it, the spec that designs it, and the scenarios
that check it. Scenario IDs are defined in the specs' acceptance criteria. Module-scoped
decisions are cited as `<module> LOCAL-NNN`.

| Requirement | Decided in | Specified in | Verified by |
| --- | --- | --- | --- |
| REQ-01 one identity | [zitadel LOCAL-001](modules/openid-connect-zitadel/adr/LOCAL-001-oidc-provider-zitadel.md), [ADR 007](adr/007-modules-receive-credentials.md), [ADR 011](adr/011-environments-are-clusters.md), [observability LOCAL-005](modules/observability-grafana-lgtm/adr/LOCAL-005-two-grafana-roles-strict.md) | [openid-connect-zitadel](modules/openid-connect-zitadel/README.md), [observability-grafana-lgtm](modules/observability-grafana-lgtm/README.md) | OIDC-01, OIDC-02, OIDC-03, LGTM-12, LGTM-13 |
| REQ-02 independent signals | [observability LOCAL-001](modules/observability-grafana-lgtm/adr/LOCAL-001-grafana-lgtm-stack.md) | [observability-grafana-lgtm](modules/observability-grafana-lgtm/README.md) | LGTM-01, LGTM-02, LGTM-03, LGTM-07 |
| REQ-03 one query surface | [observability LOCAL-001](modules/observability-grafana-lgtm/adr/LOCAL-001-grafana-lgtm-stack.md) | [observability-grafana-lgtm](modules/observability-grafana-lgtm/README.md) | LGTM-04 |
| REQ-04 durable secrets | [openbao LOCAL-001](modules/secret-manager-openbao/adr/LOCAL-001-openbao-and-eso.md), [openbao LOCAL-002](modules/secret-manager-openbao/adr/LOCAL-002-openbao-seal.md) | [secret-manager-openbao](modules/secret-manager-openbao/README.md) | SEC-01, SEC-02, SEC-04 |
| REQ-05 no plaintext credential | [ADR 007](adr/007-modules-receive-credentials.md), [openbao LOCAL-001](modules/secret-manager-openbao/adr/LOCAL-001-openbao-and-eso.md) | [platform](platform.md) | PLAT-02, OIDC-05, AUD-02 |
| REQ-06 closed by default | [ADR 007](adr/007-modules-receive-credentials.md), [observability LOCAL-005](modules/observability-grafana-lgtm/adr/LOCAL-005-two-grafana-roles-strict.md) | [platform](platform.md) | PLAT-03, PLAT-04, LGTM-05, SEC-03, AUD-04 |
| REQ-07 audit records | [ADR 008](adr/008-postgresql-is-external.md), [ADR 010](adr/010-resources-delivered-via-chart.md) | [audit-management-auditum](modules/audit-management-auditum/README.md) | AUD-01, AUD-03, AUD-05 |
| REQ-08 declared state | [ADR 005](adr/005-modules-are-applicationsets.md), [ADR 010](adr/010-resources-delivered-via-chart.md) | [platform](platform.md) | PLAT-01 |
| REQ-09 swappable implementations | [ADR 004](adr/004-scrape-config-via-prometheus-crds.md), [ADR 007](adr/007-modules-receive-credentials.md), [zitadel LOCAL-001](modules/openid-connect-zitadel/adr/LOCAL-001-oidc-provider-zitadel.md), [observability LOCAL-003](modules/observability-grafana-lgtm/adr/LOCAL-003-scrape-first-one-otlp-address.md) | [platform](platform.md) | OIDC-01, LGTM-06, LGTM-08 |
| REQ-10 fits a tiny cluster | [zitadel LOCAL-001](modules/openid-connect-zitadel/adr/LOCAL-001-oidc-provider-zitadel.md), [observability LOCAL-001](modules/observability-grafana-lgtm/adr/LOCAL-001-grafana-lgtm-stack.md), [observability LOCAL-002](modules/observability-grafana-lgtm/adr/LOCAL-002-mimir-monolithic-chart.md), [observability LOCAL-004](modules/observability-grafana-lgtm/adr/LOCAL-004-no-alerting.md), [ADR 011](adr/011-environments-are-clusters.md) | [platform](platform.md) | OIDC-04, LGTM-09 |
| REQ-11 recoverable decisions | every ADR | this repository | — |
| REQ-12 environments don't interfere | [ADR 011](adr/011-environments-are-clusters.md), [ADR 012](adr/012-state-is-per-environment.md) | [platform](platform.md) | PLAT-05 |

REQ-11 has no scenario because it is checked by a person reading, not by a machine asserting.
It is listed anyway, because it is the requirement that justifies the ADRs existing at all.

## Open questions

Each is owned by the ADR or spec that would resolve it.

- **What is REQ-07 actually about?** Application audit trails, or Kubernetes API audit logs?
  These are different systems and only one of them is Auditum. Until this is answered, REQ-07
  is not one requirement but two candidates wearing one name — see
  [audit-management-auditum](modules/audit-management-auditum/README.md#blocking-question).
- **How does OpenBao unseal?** REQ-04 is satisfiable several ways, each with a different cost,
  and the choice has not been made — see
  [openbao LOCAL-002](modules/secret-manager-openbao/adr/LOCAL-002-openbao-seal.md). With
  environments as separate clusters, whatever is chosen is operated once per environment.
- **Which state backend?** Per-environment state is settled; the backend is not — see
  [ADR 012](adr/012-state-is-per-environment.md).
- **Backup is out of scope, and REQ-04 leans on it.** Secrets surviving a rebuild is only true
  while OpenBao's storage survives. Nothing in this repo makes that so, in any environment.
