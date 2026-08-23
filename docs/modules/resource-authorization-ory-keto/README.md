# Module: resource-authorization-ory-keto

**Status:** implemented ·
**Satisfies:** [REQ-05, REQ-06, REQ-08, REQ-09, REQ-13](../../requirements.md) ·
**Decisions:** [LOCAL-001](adr/LOCAL-001-the-store-is-ory-keto.md),
[ADR 005](../../adr/005-modules-are-applicationsets.md),
[ADR 007](../../adr/007-modules-receive-credentials.md),
[ADR 008](../../adr/008-postgresql-is-external.md),
[ADR 010](../../adr/010-resources-delivered-via-chart.md),
[ADR 016](../../adr/016-metrics-is-the-fourth-input.md),
[ADR 022](../../adr/022-secrets-are-rendered-empty.md),
[ADR 026](../../adr/026-roles-decide-the-operation-relationships-decide-the-resource.md),
[ADR 027](../../adr/027-charts-are-first-class-artifacts.md),
[ADR 028](../../adr/028-a-module-renders-the-network-policy-it-depends-on.md)

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

| Wave | Application | Chart | Condition |
| --- | --- | --- | --- |
| 0 | `keto-db-credentials` | `secret-template` — imported, see [ADR 022](../../adr/022-secrets-are-rendered-empty.md) | `database_secret_name` is null |
| 1 | `keto` | `ory-keto` — authored here, wrapping Ory's `keto` | always |

**The chart is wrapped rather than native** ([ADR 010](../../adr/010-resources-delivered-via-chart.md))
because the two things that make this module what it is are both outside what upstream renders:
its chart has no `NetworkPolicy` template and no way to create the ConfigMap the model is read
from — it can mount one, not produce one. `ory-keto` declares Ory's chart as a dependency and adds
those two templates ([ADR 027](../../adr/027-charts-are-first-class-artifacts.md)).

The store runs as one instance. Two service ports, and the difference between them is the whole
security design:

| Port | Serves | Reachable from |
| --- | --- | --- |
| read | `check`, `expand`, and listing tuples | any namespace in the cluster, unauthenticated |
| write | creating, updating and deleting tuples | only the workloads `write_access_from` names |

The read port is open because every authorization decision an application makes is a call to it,
and requiring a token on that path means a client registration per application and a refresh that
can fail unattended. The cost is that any pod can enumerate the permission graph — see
[Open items](#open-items).

The write port carries a `NetworkPolicy`
([ADR 028](../../adr/028-a-module-renders-the-network-policy-it-depends-on.md)). **The rule that
re-opens the read port is not redundant**: a policy selecting these pods switches them to
default-deny, so a policy naming only the write port closes the read port with it — and the
symptom is every application in the cluster timing out against a store that reconciles healthy.

### Migrations

The store does not serve until its schema exists, and the chart runs the migration as a job before
the deployment becomes ready. **A version bump is a migration**, not only an image change, and a
rollback is not symmetric: a schema that has moved forward does not move back because the pin did.

### The model

**The model is the schema of the permission graph; the tuples are its data.** A tuple says
*`user:alice` is `owner` of `document:42`*, and is written at runtime by the application that
grants the access — usually in the same request that creates the thing being granted. The model
says what a `document` is, what relations it has, and what they imply, and it is what turns
*"is there a tuple"* into *"may alice view this", derived through the graph*.

It is written in the Ory Permission Language, a syntactic subset of TypeScript, and it lives in
this repository ([REQ-08](../../requirements.md)). `ory-keto` renders it into a ConfigMap, mounts
it, and points the store at the mounted path — so what the store enforces is what the repository
says.

**Applied on sync, not merged.** A namespace removed from the model is a namespace removed from
the store, and the tuples that referenced it go with it.

**There are two ways to say it and never both.** `model.content` is a model somebody wrote,
passed through verbatim. `model.namespaces` describes the same thing as data and this module
generates the language from it. At the root the file half is a path — `model.file` — because a
relative path has to be read where it was written.

| | Renders |
| --- | --- |
| `{ relation = "owners" }` | `this.related.owners.includes(ctx.subject)` |
| `{ permit = "edit" }` | `this.permits.edit(ctx)` |
| `{ traverse = { relation = "parents", permit = "view" } }` | `this.related.parents.traverse((v) => v.permits.view(ctx))` |

composed by `any_of` or `all_of`, and `Group#members` is the compact spelling of
`SubjectSet<Group, "members">`.

**The generated form is deliberately a subset**: one level of composition, those three terms, and
no negation — negation would make the graph non-monotonic, where adding a tuple can *remove*
access. A model needing more has outgrown the structured form and takes `content`. **The escape
hatch is the feature**, which is why both inputs exist rather than one replacing the other.

**What generating buys is checking.** A model written by hand is parsed by nothing until the store
reads it at boot; the structured form is checked at plan time — every relation target resolves,
every subject set names a relation that exists, every term references something its own namespace
declares, and **no name is both a relation and a permit in one namespace**. That last one is the
defect [LOCAL-001](adr/LOCAL-001-the-store-is-ory-keto.md) records upstream having to fix because
it *shadowed silently and made checks return wrong answers* — the class that fails open. Refusing
it in a plan is earlier than refusing it at boot.

**Leaving `model` unset ships a default that grants nothing.** It declares one namespace to hold
the subjects an issuer mints, and no object types, no relations and no permits — so there is no
rule for a derived question to match. That is a working store which authorizes nobody, and it is
the right thing to run before there is an application whose objects are worth describing. The
first application that needs a permission brings a model with it, and overriding is one input.

**Null and the empty model are different things.** An empty file is a parse error at boot; null is
how an environment asks for the default. The module refuses an empty string rather than letting it
through to become a crash loop.

## Prerequisites

**A PostgreSQL database**, reachable, with a role that owns it
([ADR 008](../../adr/008-postgresql-is-external.md)). There is no embedded fallback worth running:
tuples are the authorization state, and the store does not start without somewhere to keep them.

**Its credential, filled in.** With `database_secret_name` left null the Secret is rendered by this
module — empty, with a single `dsn` key — and its contents are ignored on every sync
([ADR 022](../../adr/022-secrets-are-rendered-empty.md)). **It is named `keto-db-credentials`, and
that name is fixed rather than derived**, because nothing publishes it and this is where an
operator reads it. Naming an existing Secret instead means this module only reads it:

```sh
kubectl patch secret keto-db-credentials -n security --type merge -p "$(jq -n \
  --arg d "$(printf %s "postgres://$DB_USER:$DB_PASSWORD@postgres.lab.internal:5432/keto?sslmode=require" | base64)" \
  '{data:{dsn:$d}}')"

kubectl rollout restart deployment/keto -n security
```

**One key, and the whole connection string is in it.** The store reads a `DSN` environment
variable from that Secret's `dsn` key and takes nothing else — so the host, the database name and
the sslmode are *inside the credential* rather than beside it. That is why this module takes a
Secret name and no `database` object at all: a `host_port` here would be a second statement of
something the Secret already carries, and the two would drift the first time a PostgreSQL moved
([§3.4](../../../CONSTITUTION.md#3-module-inputs)). The key is fixed too — the chart hard-codes
`dsn`, so naming it would be a knob with one setting.

**A cluster that enforces `NetworkPolicy`**, which is [an assumption of this
repository](../../../README.md#assumptions) rather than a prerequisite of this module — k3s
enforces them unless started with `--disable-network-policy`. Where nothing enforces, the policy
reconciles healthy and the write port is open to every pod, with no symptom. Confirm once per
environment:

```sh
kubectl run netpol-probe --rm -it --image=curlimages/curl --restart=Never -n default -- \
  curl -sS -m 5 http://keto-write.security.svc.cluster.local/relation-tuples
```

**Port 80, not 4467.** The chart's write Service listens on 80 and targets the container's 4467;
the policy names 4467 because a `NetworkPolicy` applies at the pod. Probing 4467 through the
Service reaches nothing whether the policy works or not, which is the one result that proves
neither thing.

A connection that hangs or is refused is the policy working. A response is the policy doing
nothing.

**Applications that write their own tuples.** Nothing in this module authenticates a caller and
nothing in front of it does either — `write_access_from` names the workloads allowed to reach the
port, and reaching it is the whole of the permission. That is why nothing outside the cluster can
write: there is no identity to check, only an address to be reachable from.

## Inputs

```hcl
namespace = "security"

# Null: this module renders the placeholder, named keto-db-credentials, with one empty `dsn` key.
# Set: an existing Secret this module only reads.
database_secret_name = null

# The workloads permitted to reach the write port — one entry each, pod labels matched in the
# namespace named beside them. These are applications: whichever grants access to a resource it
# owns writes the tuple. Empty is refused, because a store nothing may write to is one nobody can
# configure.
write_access_from = {
  reports = {
    namespace = "apps"
    labels    = { "app.kubernetes.io/name" = "reports" }
  }
}

# The permission model, said one of two ways. Null — the default — grants nobody anything.
model = {
  namespaces = {
    User  = {}
    Group = { relations = { members = ["User"] } }
    Folder = {
      relations = { owners = ["User", "Group#members"], parents = ["Folder"] }
      permits = {
        view = { any_of = [
          { relation = "owners" },
          { traverse = { relation = "parents", permit = "view" } },
        ] }
      }
    }
  }
}

# ...or a model somebody wrote. The root reads it from a path with `model.file`; what reaches this
# module is the text.
model = { content = file("opl/lab.ts") }

metrics = { enabled = true, tenant = "security" }
```

**`write_access_from` holds selectors, not module references.** The workloads it names are
applications this repository does not deploy — it provisions platform capabilities, not the things
that consume them — so there is no module output to read them from and the composing root states
them ([§4.2](../../../CONSTITUTION.md#4-composition)). It is a dedicated input because nothing else
this module takes names those callers
([ADR 028](../../adr/028-a-module-renders-the-network-policy-it-depends-on.md)).

**Each entry is one caller, and several are an OR.** A namespace and its labels go into one `from`
element, which is an AND; entries are separate elements, which is what makes two applications two
permitted callers rather than one impossible condition.

**There is no `gateway`.** Nothing here is routed, and nothing here can be: both ports are
in-cluster addresses, and the write port has no authentication in front of it to make exposing it
survivable.

Plus two inputs no environment normally writes: `argocd.namespace`, where the `ApplicationSet`
object goes, and `git_repository`, this repository and the revision Argo CD reads its charts at,
which every module rendering one of them takes. This module renders two, so it is always
consulted.

**There is no chart-version input**, because both charts are this repository's and are read from
git — `git_repository.revision` *is* the pin. The upstream store chart's version is pinned where
it is resolved, in [`helm/ory-keto`](../../../helm/ory-keto)'s `Chart.yaml` dependency, and a
number repeated here would be one nothing reads.

## Outputs

| Output | Used by |
| --- | --- |
| `read_url` | applications, as the address to ask authorization questions of |
| `write_url` | the applications that create tuples when they grant access |

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
    Given database_secret_name is set
    When the rendered Helm values are read
    Then no connection string appears in them
     And the store is configured to read DSN from the named Secret

  @plan
  Scenario: [AUTHZ-03] The placeholder arrives with its key, and is never overwritten
    Given database_secret_name is null
    When the rendered resources are read
    Then a Secret named keto-db-credentials is created carrying dsn with an empty value
     And the Application ignores differences on its .data
     And RespectIgnoreDifferences is set

  @plan
  Scenario: [AUTHZ-04] The write port is restricted and the read port is re-opened
    Given write_access_from names two workloads in different namespaces
    When the rendered NetworkPolicy is read
    Then ingress to the write port is allowed only from those two
     And each is one from element carrying both a namespaceSelector and a podSelector
     And a second rule allows ingress to the read port from anywhere
     And policyTypes names Ingress and not Egress

  @plan
  Scenario: [AUTHZ-05] Nothing may write when nothing is named
    Given write_access_from is empty
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
  Scenario: [AUTHZ-08] A pod outside every selector cannot write
    Given the module is applied and the cluster enforces NetworkPolicy
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

  @plan
  Scenario: [AUTHZ-13] A structured model becomes the language
    Given model.namespaces declares a relation and a permit that traverses it
    When the rendered Helm values are read
    Then the model content declares that namespace as a class
     And the permit renders as a traverse over that relation

  @plan
  Scenario: [AUTHZ-14] A name that is both a relation and a permit is refused
    Given model.namespaces gives one namespace a relation and a permit of the same name
    When the module is planned
    Then the plan is refused before the store ever parses it

  @plan
  Scenario: [AUTHZ-15] The two ways of saying it are exclusive
    Given both model.content and model.namespaces are set
    When the module is planned
    Then the plan is refused naming both

  @plan
  Scenario: [AUTHZ-12] An unset model ships the default rather than an empty one
    Given model is null
    When the rendered Helm values are read
    Then they carry no model content
     And the chart's own default is what reaches the ConfigMap

  @cluster
  Scenario: [AUTHZ-11] The read port survives the policy
    Given the module is applied and the cluster enforces NetworkPolicy
    When a pod in another namespace calls check on the read port
    Then it receives an answer
     And the NetworkPolicy is present in the namespace
```

## Open items

- **Every `@cluster` criterion is unverified.** AUTHZ-07, AUTHZ-08, AUTHZ-09, AUTHZ-10 and AUTHZ-11 have never been run: Argo CD for these
  environments is on a home network no runner reaches, and nothing here has been applied to a
  cluster. The `@plan` criteria are what the composition has actually been checked against.
- **Any pod can read the whole permission graph.** The read port answers `check` and `expand`, and
  it also enumerates tuples — so leaving it open to the cluster means every workload can discover
  who may do what to what. This is disclosure rather than compromise, and it was chosen for the hot
  path ([LOCAL-001](adr/LOCAL-001-the-store-is-ory-keto.md)). Narrowing it means naming every
  application that will ever ask a question, including the ones not written yet. Worth revisiting
  if anything untrusted is ever scheduled here.
- **Nothing verifies the `NetworkPolicy` is enforced**, and the failure is silent and total
  ([ADR 028](../../adr/028-a-module-renders-the-network-policy-it-depends-on.md)). The probe in
  [Prerequisites](#prerequisites) is a manual check run once per environment, which is a runbook
  step and not a guarantee. Making `AUTHZ-08` part of a real harness is what would close this.
- **Tuples are in PostgreSQL and nothing backs it up.** They are the third thing in that database
  that cannot be regenerated from git, and unlike the issuer's realm or the console's alert rules,
  losing them is a silent change in what people can reach rather than an obvious outage. The model
  survives — it is in this repository — and the relations do not.
- **The model is not portable.** Moving to another relationship store means rewriting it and
  migrating every tuple. Consumers are unaffected, since they hold an address; whoever does the
  moving is not.
- **The model changes without a version bump anywhere.** It is an input to this module rather than
  a value of the chart, so editing it changes what the store enforces with nothing recording that
  a boundary moved. A tuple written against a relation that later disappears is a permission that
  silently stops resolving.
- **There is no administration interface.** Inspecting why a check returned what it did is the
  `keto` CLI through a port-forward. That is adequate for one operator and would not be for a team,
  and no upstream UI exists to adopt.
