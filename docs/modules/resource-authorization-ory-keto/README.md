# Module: resource-authorization-ory-keto

**Status:** draft ·
**Satisfies:** [REQ-05, REQ-06, REQ-08, REQ-09, REQ-13](../../requirements.md) ·
**Decisions:** [LOCAL-001](adr/LOCAL-001-the-store-is-ory-keto.md),
[LOCAL-002](adr/LOCAL-002-the-write-port-admits-only-its-caller.md),
[ADR 005](../../adr/005-modules-are-applicationsets.md),
[ADR 007](../../adr/007-modules-receive-credentials.md),
[ADR 008](../../adr/008-postgresql-is-external.md),
[ADR 010](../../adr/010-resources-delivered-via-chart.md),
[ADR 016](../../adr/016-metrics-is-the-fourth-input.md),
[ADR 022](../../adr/022-secrets-are-rendered-empty.md),
[ADR 026](../../adr/026-roles-decide-the-operation-relationships-decide-the-resource.md)

## Intent

**One place that answers "may this subject do this to this object".** Roles in a token already say
whether somebody may use a service at all; this says whether they may act on a particular thing
inside it ([ADR 026](../../adr/026-roles-decide-the-operation-relationships-decide-the-resource.md)).

Its consumers are applications deployed into the environment, not the platform modules here. None
of those needs it: they authorize coarse access to their own interfaces and nothing finer. This
module exists so that an application does not answer the question privately, in its own table,
with its own idea of what absence means.

**It is not an identity source.** It holds no users and no credentials — only subject identifiers
the issuer minted, and the relations between them and the objects an application owns.

## Provisions

One `ApplicationSet` ([ADR 005](../../adr/005-modules-are-applicationsets.md)) with a `List`
generator, holding:

| Application | Chart | Case |
| --- | --- | --- |
| the store | Ory's `keto` chart, pinned | native |
| the placeholder Secret | `modules/secret-template`, when `database.secret_name` is null | — |

The store runs as one instance. Two service ports, and the difference between them is the whole
security design:

| Port | Serves | Reachable from |
| --- | --- | --- |
| read | `check`, `expand`, and listing tuples | any namespace in the cluster, unauthenticated |
| write | creating, updating and deleting tuples | only the selector `write_access_from` names |

The read port is open because every authorization decision an application makes is a call to it,
and requiring a token on that path means a client registration per application and a refresh that
can fail unattended. The cost is that any pod can enumerate the permission graph — see
[Open items](#open-items).

The write port carries a `NetworkPolicy`
([LOCAL-002](adr/LOCAL-002-the-write-port-admits-only-its-caller.md)). **This module renders the
only `NetworkPolicy` in this repository and that is an exception, not a pattern** — a second module
wanting one makes the decision platform-scoped.

### Migrations

The store does not serve until its schema exists, and the chart runs the migration as a job before
the deployment becomes ready. **A version bump is a migration**, not only an image change, and a
rollback is not symmetric: a schema that has moved forward does not move back because the pin did.

### The model

Namespaces and their relations are the Ory Permission Language, held in this module's values and
rendered into the store's configuration — so what the store enforces is what the repository says
([REQ-08](../../requirements.md)). Tuples are not: those are written at runtime, by applications
and by whatever configures them from outside
([`access-proxy-ory-oathkeeper`](../access-proxy-ory-oathkeeper/README.md) is what lets them).

## Prerequisites

**A PostgreSQL database**, reachable, with a role that owns it
([ADR 008](../../adr/008-postgresql-is-external.md)). There is no embedded fallback worth running:
tuples are the authorization state, and the store does not start without somewhere to keep them.

**Its credential, filled in.** With `database.secret_name` left null the Secret is rendered by this
module — empty, with `username` and `password` present — and its contents are ignored on every sync
([ADR 022](../../adr/022-secrets-are-rendered-empty.md)). Naming an existing Secret instead means
this module only reads it:

```sh
kubectl patch secret keto-db-credentials -n security --type merge -p "$(jq -n \
  --arg u "$(printf %s "$DB_USER" | base64)" \
  --arg p "$(printf %s "$DB_PASSWORD" | base64)" '{data:{username:$u,password:$p}}')"

kubectl rollout restart deployment/keto -n security
```

**A CNI that enforces `NetworkPolicy`.** The cluster is a prerequisite this repository never
provisions ([§1.1](../../../CONSTITUTION.md#1-boundaries)), and **nothing here checks this**. Where
it is not enforced the policy reconciles healthy and the write port is open to every pod in the
cluster, with no symptom. Confirm it once per environment:

```sh
kubectl run netpol-probe --rm -it --image=curlimages/curl --restart=Never -n default -- \
  curl -sS -m 5 http://keto-write.security.svc.cluster.local:4467/relation-tuples
```

A connection that hangs or is refused is the policy working. A response is the policy doing
nothing.

**Something to reach the write port.** Nothing in this module authenticates a caller; that is
[`access-proxy-ory-oathkeeper`](../access-proxy-ory-oathkeeper/README.md), and `write_access_from`
is how the two are joined.

## Inputs

```hcl
namespace = "security"

database = {
  host_port     = "postgres.lab.internal:5432"
  database_name = "keto"
  # secret_name unset: this module renders the placeholder and publishes the name it chose
}

# The workload permitted to reach the write port. Pod labels, matched in the namespace named
# beside them. Unset means nothing may write — which is a working store nobody can configure.
write_access_from = {
  namespace = "security"
  labels    = { "app.kubernetes.io/name" = "oathkeeper" }
}

# The permission model. Namespaces and their relations, in the Ory Permission Language.
model = file("${path.module}/opl/lab.ts")

metrics = { enabled = true, tenant = "security" }
```

**`write_access_from` is a selector and not a module reference.** Which workload it names is the
root's business — that is what keeps this module's network decision its own
([LOCAL-002](adr/LOCAL-002-the-write-port-admits-only-its-caller.md)) rather than a platform one
wearing a module's number.

**There is no `gateway`.** Nothing here is routed. The read port is in-cluster and the write port
is reached through the proxy, which owns the route.

**`model` is applied on sync, not merged.** What the repository says is what the store enforces; a
namespace removed from this input is a namespace removed from the store, and the tuples that
referenced it go with it.

Plus two inputs no environment normally writes: `keto.chart_version`, the pin — and the only place
that version is written, since a value set at the root would not add a second opinion but replace
this one silently; and `argocd.namespace`, where the `ApplicationSet` object goes.

## Outputs

| Output | Used by |
| --- | --- |
| `read_url` | applications, as the address to ask authorization questions of |
| `write_url` | the access proxy, as the upstream it fronts |
| `database_secret_name` | the operator, to know what to fill in |

**Two addresses rather than one, because they are not the same trust level.** A consumer given the
read address cannot write no matter what it does with it, and that is a property of the address
rather than of a credential it holds.

No output carries a credential, and none names the model — an application that needs to know what
relations exist reads this repository, not the store.

## Acceptance criteria

Scenario IDs are `AUTHZ-NN`.

```gherkin
Feature: Resource-level authorization, asked per decision

  @plan
  Scenario: [AUTHZ-01] One ApplicationSet, never a bare Application
    Given the module is planned
    When the rendered resources are read
    Then exactly one ApplicationSet is created
     And it uses a List generator
     And no bare Application is created

  @plan
  Scenario: [AUTHZ-02] The credential is never rendered
    Given a database secret_name is set
    When the rendered Helm values are read
    Then no username or password value appears in them
     And the store is configured to read them from the named Secret

  @plan
  Scenario: [AUTHZ-03] The placeholder arrives with its keys, and is never overwritten
    Given database.secret_name is null
    When the rendered resources are read
    Then a Secret is created carrying username and password with empty values
     And the Application ignores differences on its .data
     And RespectIgnoreDifferences is set

  @plan
  Scenario: [AUTHZ-04] The write port is restricted and the read port is not
    Given write_access_from names a namespace and labels
    When the rendered NetworkPolicy is read
    Then ingress to the write port is allowed only from that selector
     And ingress to the read port is not restricted

  @plan
  Scenario: [AUTHZ-05] Nothing may write when nothing is named
    Given write_access_from is null
    When the module is planned
    Then the plan is refused with a message naming write_access_from

  @plan
  Scenario: [AUTHZ-06] Nothing is routed
    Given the module is planned
    When the rendered resources are read
    Then no HTTPRoute is created
     And no Gateway is referenced

  @cluster
  Scenario: [AUTHZ-07] The schema exists before the store serves
    Given the module is applied to a cluster with an empty database
    When the Application reaches Synced
    Then the migration job completed before the deployment became ready

  @cluster
  Scenario: [AUTHZ-08] A pod outside the selector cannot write
    Given the module is applied and the CNI enforces NetworkPolicy
    When a pod in another namespace posts a relation tuple to the write port
    Then the connection is refused or times out

  @cluster
  Scenario: [AUTHZ-09] Any pod may ask
    Given the module is applied
    When a pod in another namespace calls check on the read port
    Then it receives an answer without presenting a credential

  @cluster
  Scenario: [AUTHZ-10] The model in the repository is the model in the store
    Given the model input declares a namespace
    When the store's configuration is read from the running pod
    Then that namespace and its relations are present
     And no namespace absent from the input is present
```

## Open items

- **Any pod can read the whole permission graph.** The read port answers `check` and `expand`, and
  it also enumerates tuples — so leaving it open to the cluster means every workload can discover
  who may do what to what. This is disclosure rather than compromise, and it was chosen for the hot
  path ([LOCAL-001](adr/LOCAL-001-the-store-is-ory-keto.md)). Narrowing it means naming every
  application that will ever ask a question, including the ones not written yet. Worth revisiting
  if anything untrusted is ever scheduled here.
- **Nothing verifies the `NetworkPolicy` is enforced**, and the failure is silent and total
  ([LOCAL-002](adr/LOCAL-002-the-write-port-admits-only-its-caller.md)). The probe in
  [Prerequisites](#prerequisites) is a manual check run once per environment, which is a runbook
  step and not a guarantee. Making `AUTHZ-08` part of a real harness is what would close this.
- **Tuples are in PostgreSQL and nothing backs it up.** They are the third thing in that database
  that cannot be regenerated from git, and unlike the issuer's realm or the console's alert rules,
  losing them is a silent change in what people can reach rather than an obvious outage. The model
  survives — it is in this repository — and the relations do not.
- **The model is not portable.** Moving to another relationship store means rewriting it and
  migrating every tuple. Consumers are unaffected, since they hold an address; whoever does the
  moving is not.
- **There is no administration interface.** Inspecting why a check returned what it did is the
  `keto` CLI through a port-forward. That is adequate for one operator and would not be for a team,
  and no upstream UI exists to adopt.
