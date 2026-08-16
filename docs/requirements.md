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
| REQ-02 | Metrics, logs and traces are each shipped or omitted independently. Whatever is present works on its own. | An environment wants one of them long before it wants three, and paying for the other two meanwhile is the whole cost problem. |
| REQ-03 | Whatever observability is switched on is queried from one place. | Two query UIs is one more than a single operator will keep in their head. |
| REQ-05 | No credential is written into declared configuration — not into git, not into OpenTofu state, not into the Helm values rendered inside an `Application`. | Anything in a `values.yaml` ends up rendered into an object in etcd in plaintext, readable by anyone who can read that object. |
| REQ-06 | A workload is unreachable from outside its cluster unless it has been deliberately exposed. | Exposure should be an act, not the default that nobody noticed. |
| REQ-07 | Applications have somewhere to write audit records that survives a restart and can be queried. | *Blocked — see [the open questions](#open-questions).* |
| REQ-08 | Every resource this repo provisions is reconciled from a declared source. Nothing it provisions is applied by hand; nothing drifts silently. | The point of the whole exercise is that a cluster matches something readable. |
| REQ-09 | Replacing the product behind a capability does not change what consumes it. | Every choice below was made once, on partial information, and at least one will turn out wrong. |
| REQ-10 | Standing resource cost stays proportionate to a tiny k3s cluster, per environment. An environment does not pay for capability it does not ship. | RAM is the real budget, spent all day, every day, and now spent once per environment. |
| REQ-11 | Six months later, a maintainer can find out what runs, why it was chosen, and what breaks if they change it. | This is the actual measure of success. Uptime is not. |
| REQ-12 | Environments do not interfere with one another. Each is configured independently. | A change or an outage in one must not be visible in another — otherwise there is one environment wearing several names. |
| REQ-13 | What a person may do in a service is decided by the environment's issuer, not by that service's own permission list. A person with no permission stated gets none. | REQ-01 stops each workload keeping its own *users*. Without this, they each keep their own *permissions* instead, which is the same problem one layer down. |
| REQ-15 | No single source of telemetry can consume the storage the others depend on. | Disk is the scarce resource, an ingest endpoint has no natural ceiling, and one misbehaving writer would otherwise cost every signal at once — the failure REQ-06's boundary and [ADR 014](adr/014-exposed-does-not-mean-authorized.md) both name and neither bounds. |
| REQ-14 | Traffic entering an environment from outside its cluster is encrypted. Every certificate that makes that true — and any the environment needs in order to authenticate a machine caller — is issued from a declared source and never made by hand. | A certificate is the one credential that expires on a schedule. A hand-made one is a resource nobody renews and nothing records, which is REQ-08's problem arriving with a deadline attached. |

**REQ-04 was dropped**, along with the module that satisfied it. It required credentials to
survive a cluster rebuild, and nothing currently in scope delivers that — see
[the open questions](#open-questions). The number is not reused, for the same reason the ADR
sequence keeps its gaps: it usefully marks something that was once here.

**REQ-02's boundary.** Independence is about what an environment ships, not about how good the
result is. A signal that is absent costs cross-signal navigation — a metric with no traces
behind it has nothing to link to — and never the availability of what is present. REQ-03 is
satisfied by whichever signals are switched on, not by all three.

**REQ-05's boundary.** It governs *declared* configuration, which is where a credential would
otherwise be copied and forgotten
([ADR 007](adr/007-modules-receive-credentials.md), rule 1). It does not make the Secret itself
unreadable: that object lives in etcd, unencrypted at rest under k3s defaults, and is readable
by anything holding RBAC to read it. Narrowing *that* exposure is secret storage, which is out
of scope and unsolved — see [the open questions](#open-questions).

**REQ-06's boundary.** It claims *reachability* — that exposure is an act rather than a default
— and says nothing about what happens to a request once it arrives. Every exposed surface here
was a UI that authorizes itself until the observability storage module began routing an OTLP
ingest endpoint, which has no notion of a person and nothing in this repo gives it one.
Authorization on such an endpoint belongs to the Gateway, and the Gateway is a per-environment
prerequisite this repo never provisions
([ADR 014](adr/014-exposed-does-not-mean-authorized.md), and `OBS-21` checks that the endpoint
is write-only whatever the listener demands, while `OBS-23` checks that the listener is what
decides who may write). The gap is deliberate; REQ-06 is simply not claiming more than it
delivers, and [REQ-14](#the-requirements) provisions the material for an environment that wants
to close it.

**REQ-08's boundary.** *Provisions* is the operative word. Cluster bootstrap, Argo CD itself,
Traefik and the Gateway, and PostgreSQL are per-environment prerequisites this repo never
creates ([platform scope](platform.md#scope)) — and every Secret a module references is created
by hand today. An alert rule authored in Grafana's UI is in the same category: this repo
provisions no alert rule, so one that exists is outside the claim rather than in violation of
it. REQ-08 claims reconciliation over what this repo declares, not over everything running in
the cluster.

**REQ-12's boundary.** It covers everything this repo provisions: separate clusters, separate
Argo CDs, separate state. It does not cover shared external dependencies — one PostgreSQL
server hosting databases for two environments still couples them, and nothing here prevents
that. Modules are correctly indifferent
([ADR 007](adr/007-modules-receive-credentials.md)); the requirement is simply not claiming
more than it delivers.

**REQ-14's boundary.** It claims *issuance* and *encryption*, and nothing about enforcement. That
an exposed endpoint demands a client certificate is a property of the environment's Gateway,
which this repo never provisions
([ADR 014](adr/014-exposed-does-not-mean-authorized.md), [platform scope](platform.md#scope)).
What this requirement changes is that the material exists and is declared — where ADR 014 was
written, closing that gap meant owning a Gateway, and it does not any more. It also says nothing
about *who* trusts these certificates: they are issued by an authority this repo owns
([cert-manager LOCAL-001](modules/certificate-management-cert-manager/adr/LOCAL-001-certificates-from-an-internal-ca.md)),
so trust is distributed rather than assumed, and that cost is the decision's, not the
requirement's.

## Traceability

Each requirement, the decisions that resolve it, the spec that designs it, and the scenarios
that check it. Scenario IDs are defined in the specs' acceptance criteria. Module-scoped
decisions are cited as `<module> LOCAL-NNN`.

**A scenario absent from this table verifies a decision rather than a requirement**, and the
decision is among those its spec's header lists. `CON-10` checks that nothing is provisioned to
alert, which is `observability-console-grafana LOCAL-003`'s consequence and no requirement's;
`CERT-06` and `CERT-08` check input validations; `OBS-27` and `OBJ-06` through `OBJ-09` check
consequences of the decision to put the stores' data in an object store. Absence here is a statement rather than an omission — a
scenario that verifies neither a requirement nor a decision its spec cites should not exist.

| Requirement | Decided in | Specified in | Verified by |
| --- | --- | --- | --- |
| REQ-01 one identity | [keycloak LOCAL-001](modules/openid-connect-keycloak/adr/LOCAL-001-oidc-provider-keycloak.md), [ADR 007](adr/007-modules-receive-credentials.md), [ADR 011](adr/011-environments-are-clusters.md), [ADR 018](adr/018-one-trust-bundle-for-the-cluster.md) | [openid-connect-keycloak](modules/openid-connect-keycloak/README.md) | OIDC-01, OIDC-02, OIDC-03, CON-08, CON-13 |
| REQ-02 independent signals | [observability-storage-grafana-lgtm LOCAL-001](modules/observability-storage-grafana-lgtm/adr/LOCAL-001-grafana-lgtm-stack.md) | [observability-storage-grafana-lgtm](modules/observability-storage-grafana-lgtm/README.md) | OBS-01, OBS-17, OBS-19, OBS-22, CON-05 |
| REQ-03 one query surface | [observability-storage-grafana-lgtm LOCAL-001](modules/observability-storage-grafana-lgtm/adr/LOCAL-001-grafana-lgtm-stack.md) | [observability-console-grafana](modules/observability-console-grafana/README.md) | CON-02, CON-03, CON-04 |
| REQ-05 no plaintext credential | [ADR 007](adr/007-modules-receive-credentials.md), [ADR 022](adr/022-secrets-are-rendered-empty.md) | [platform](platform.md) | PLAT-02, OIDC-06, AUD-02, OBJ-02, OBS-28 |
| REQ-06 closed by default | [ADR 007](adr/007-modules-receive-credentials.md), [ADR 014](adr/014-exposed-does-not-mean-authorized.md) | [platform](platform.md) | PLAT-03, PLAT-04, OBS-18, OBS-20, OBS-21, CON-06, OIDC-07, AUD-04, OBJ-13, OBJ-16 |
| REQ-07 audit records | [ADR 008](adr/008-postgresql-is-external.md), [ADR 010](adr/010-resources-delivered-via-chart.md) | [audit-management-auditum](modules/audit-management-auditum/README.md) | AUD-01, AUD-03, AUD-05 |
| REQ-08 declared state | [ADR 005](adr/005-modules-are-applicationsets.md), [ADR 010](adr/010-resources-delivered-via-chart.md), [ADR 022](adr/022-secrets-are-rendered-empty.md) | [platform](platform.md) | PLAT-01 |
| REQ-09 swappable implementations | [ADR 004](adr/004-scrape-config-via-prometheus-crds.md), [ADR 007](adr/007-modules-receive-credentials.md), [keycloak LOCAL-001](modules/openid-connect-keycloak/adr/LOCAL-001-oidc-provider-keycloak.md), [observability-storage-grafana-lgtm LOCAL-003](modules/observability-storage-grafana-lgtm/adr/LOCAL-003-scrape-first-one-otlp-address.md), [object-storage-rustfs LOCAL-001](modules/object-storage-rustfs/adr/LOCAL-001-rustfs-standalone.md) | [platform](platform.md) | OIDC-01, OBS-06, OBS-08, OBJ-03 |
| REQ-10 fits a tiny cluster | [keycloak LOCAL-001](modules/openid-connect-keycloak/adr/LOCAL-001-oidc-provider-keycloak.md), [observability-storage-grafana-lgtm LOCAL-001](modules/observability-storage-grafana-lgtm/adr/LOCAL-001-grafana-lgtm-stack.md), [observability-storage-grafana-lgtm LOCAL-002](modules/observability-storage-grafana-lgtm/adr/LOCAL-002-mimir-monolithic-chart.md), [object-storage-rustfs LOCAL-001](modules/object-storage-rustfs/adr/LOCAL-001-rustfs-standalone.md), [ADR 011](adr/011-environments-are-clusters.md) | [platform](platform.md) | OIDC-04, OBS-09, OBJ-01 |
| REQ-11 recoverable decisions | every ADR | this repository | — |
| REQ-12 environments don't interfere | [ADR 011](adr/011-environments-are-clusters.md), [ADR 012](adr/012-state-is-per-environment.md) | [platform](platform.md) | PLAT-05 |
| REQ-13 permissions come from the issuer | [ADR 013](adr/013-roles-are-carried-in-the-token.md), [observability-console-grafana LOCAL-001](modules/observability-console-grafana/adr/LOCAL-001-two-grafana-roles-strict.md) | [platform](platform.md), [observability-console-grafana](modules/observability-console-grafana/README.md) | CON-07 |
| REQ-14 certificates are issued, not made | [certificate-management-cert-manager LOCAL-001](modules/certificate-management-cert-manager/adr/LOCAL-001-certificates-from-an-internal-ca.md), [certificate-management-cert-manager LOCAL-002](modules/certificate-management-cert-manager/adr/LOCAL-002-one-certificate-per-authority.md), [ADR 014](adr/014-exposed-does-not-mean-authorized.md), [ADR 018](adr/018-one-trust-bundle-for-the-cluster.md) | [certificate-management-cert-manager](modules/certificate-management-cert-manager/README.md) | CERT-01, CERT-04, CERT-05, CERT-07, OBS-23 |
| REQ-15 no writer starves the others | [ADR 017](adr/017-stores-are-multi-tenant.md) | [observability-storage-grafana-lgtm](modules/observability-storage-grafana-lgtm/README.md), [observability-console-grafana](modules/observability-console-grafana/README.md) | OBS-24, OBS-25, OBS-26 |

REQ-11 has no scenario because it is checked by a person reading, not by a machine asserting.
It is listed anyway, because it is the requirement that justifies the ADRs existing at all.

## Open questions

Each is owned by the ADR or spec that would resolve it.

- **What is REQ-07 actually about?** Application audit trails, or Kubernetes API audit logs?
  These are different systems and only one of them is Auditum. Until this is answered, REQ-07
  is not one requirement but two candidates wearing one name — see
  [audit-management-auditum](modules/audit-management-auditum/README.md#blocking-question).
- **Nothing stores secrets. Something now creates them, empty, when nobody else has.** A module
  given no name for a credential renders the Secret itself, keys present and values blank, and
  Argo CD leaves the contents alone ([ADR 022](adr/022-secrets-are-rendered-empty.md)) — so a
  rebuild recreates every credential *object*, and what remains is discoverable by listing
  Secrets rather than by reading five specs. An environment that does have something creating
  Secrets names them instead, and no module fights it. Either way the value is typed in by a
  person, per environment, held nowhere, backed up by nothing and rotated by nothing. The by-reference contract
  ([ADR 007](adr/007-modules-receive-credentials.md)) is unaffected throughout. This is what
  dropping REQ-04 still costs, narrowed to the half that is actually a secret.
- **Nothing declares the realm.** REQ-01 and REQ-13 are satisfied by an issuer whose clients,
  roles and grants exist only in its own console — typed in by hand, per environment, and again
  after any rebuild that loses the database. The claim *shape* is fixed
  ([ADR 013](adr/013-roles-are-carried-in-the-token.md)) and its *content* is recorded nowhere,
  which is REQ-11 failing at the one place it matters most. Recording it in git is possible and
  deferred, and would be a record rather than a reconciled resource; the obstacle is REQ-05,
  because a realm export embeds client secrets — see
  [`openid-connect-keycloak`](modules/openid-connect-keycloak/README.md#open-items).
