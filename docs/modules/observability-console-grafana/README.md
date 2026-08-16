# Module: observability-console-grafana

**Status:** draft ·
**Satisfies:** [REQ-01, REQ-03, REQ-05, REQ-06, REQ-13](../../requirements.md) ·
**Decisions:** [LOCAL-001](adr/LOCAL-001-two-grafana-roles-strict.md),
[LOCAL-003](adr/LOCAL-003-alerting-lives-in-grafana.md),
[ADR 005](../../adr/005-modules-are-applicationsets.md),
[ADR 007](../../adr/007-modules-receive-credentials.md),
[ADR 010](../../adr/010-resources-delivered-via-chart.md),
[ADR 013](../../adr/013-roles-are-carried-in-the-token.md),
[ADR 016](../../adr/016-metrics-is-the-fourth-input.md),
[ADR 025](../../adr/025-a-workload-carries-its-tenant.md),
[ADR 020](../../adr/020-one-root-module.md),
[ADR 017](../../adr/017-stores-are-multi-tenant.md),
[ADR 018](../../adr/018-one-trust-bundle-for-the-cluster.md),
[ADR 022](../../adr/022-secrets-are-rendered-empty.md)

## Intent

One place to read whatever observability the environment switched on
([REQ-03](../../requirements.md)), signed into with the environment's one account
([REQ-01](../../requirements.md)), with what a person may do decided by their token
([REQ-13](../../requirements.md)).

Grafana is the console because the stores are Grafana's. That pairing is not a preference —
it is the reason the stack was chosen at all, since correlation between metrics, logs and
traces is then the product's own feature rather than something assembled here. The argument
lives with the stores, in
[`observability-storage-grafana-lgtm`](../observability-storage-grafana-lgtm/README.md)'s
`LOCAL-001`; a module ADR is local to its module, so it is restated here rather than cited.

**This module reads; it does not collect and does not store.** It was split out of what used to
be one `observability-grafana-lgtm`, on the line where the dependencies stop being shared:
Grafana needs PostgreSQL, an issuer, a route and a person, and none of those are needed to
ingest a span.

## Provisions

One Argo CD `ApplicationSet` ([ADR 005](../../adr/005-modules-are-applicationsets.md)), whose
`List` generator produces one Application, plus one per credential it is asked to render:

| Wave | Application | Chart | Condition |
| --- | --- | --- | --- |
| 0 | `grafana-db-credentials` | `secret-template` — imported, see [ADR 022](../../adr/022-secrets-are-rendered-empty.md) | `database.secret_name` is null |
| 0 | `grafana-admin-credentials` | `secret-template` | `admin.secret_name` is null |
| 0 | `grafana-oidc-credentials` | `secret-template` | `oidc` is set and `oidc.secret_name` is null |
| 1 | `grafana` | `grafana` (grafana-community) | always |

**Three credentials, one pattern, and no exceptions among them**
([ADR 022](../../adr/022-secrets-are-rendered-empty.md)). Each is either a Secret named by the
caller and only read, or a placeholder rendered here — empty, with its keys present, its `.data`
ignored on every sync. Making one of the three mandatory and the others optional would be an
inconsistency rather than a safeguard.

**The third one exists because otherwise the chart invents it.** Grafana's chart renders its own
admin Secret unless told an existing one, and the password it puts there comes from a `lookup`
of the Secret it is about to create, falling back to `randAlphaNum 40`. Argo CD generates
manifests with no cluster to look up against, so that fallback is the only branch that ever runs
and every render produces a different password. Pointing `admin.existingSecret` at a placeholder
switches the whole template off at its guard. The alternative — letting it generate one and
hiding the churn — is the case this repository treats as proof the chart is wrong, and it would
also mean the break-glass account below had a password nobody knows.

**Datasources are generated from the three address inputs crossed with the tenant list** — one
per non-`null` address, per tenant. Their *types* are not inputs: an address named `metrics_url`
becomes a `prometheus` datasource, `logs_url` a `loki` one, `traces_url` a `tempo` one. Swapping
the store behind a capability ([REQ-09](../../requirements.md)) means swapping it for something
speaking the same query API, so a type input would be flexibility nobody would ever spend.

**The tenant is a header on the datasource, not a second address.** The stores run multi-tenant
([ADR 017](../../adr/017-stores-are-multi-tenant.md)),
so every read carries `X-Scope-OrgID`. Two tenants over two switched-on signals is four
datasources, named `<store> <tenant>`, and `default_tenant` decides whose is marked as
its default.

**`tenants` is a read-side choice and cannot disagree with reality.** Nothing validates a tenant
name on write either, so there is no set of "real" tenants for this list to be wrong about — it
says which ones are worth looking at. That is why it is a root variable read by this module and
by the storage module, rather than anything passing between them
([ADR 020](../../adr/020-one-root-module.md)).

### Correlation

The reason for choosing this stack. **Each link is conditional on both of its ends existing**,
and both ends are simply two of the three addresses being non-null:

**Every link is wired within a tenant.** A trace in one tenant cannot open logs in another, and
the service graph exists only for the tenant Tempo's `metrics-generator` writes into. That is
the cost of partitioning writes, paid on the read side, and it is why `tenants` should hold the
smallest number that is actually useful.

| Datasource | Gains, when… | Link | Gives you |
| --- | --- | --- | --- |
| metrics | traces set | `exemplarTraceIdDestinations` → traces | a point on a graph opens its trace |
| logs | traces set | `derivedFields` → traces | a log line opens its trace |
| traces | logs set | `tracesToLogsV2` → logs | a span opens its logs |
| traces | metrics set | `serviceMap.datasourceUid` → metrics | the service graph |

**The service graph**, specifically, because it is the least obvious of the four and because
half of it is somebody else's job:

1. Tempo's `metrics-generator` derives `traces_service_graph_request_total` and its siblings
   from spans as they arrive, and remote-writes them into Mimir. **That half is the storage
   module's**, and it enables the generator only when metrics and traces are both on.
2. Grafana's traces datasource points `serviceMap.datasourceUid` at the metrics datasource.
3. The Service Graph tab renders from metrics; clicking a node drills back into traces.

With `metrics_url` null, step 2 is not wired and step 1 never happened, so the tab offers no
query that cannot be answered. The degradation is clean at both ends because both ends derive
from the same fact.

### Access

**Route.** Native case per [ADR 010](../../adr/010-resources-delivered-via-chart.md): Grafana's
own chart renders the `HTTPRoute` from `route.main`, populated from `var.gateway`. The chart's
own `ingress` stays disabled so there is exactly one path in. Grafana is the only thing this
module exposes, and the stores it reads are never routed by the module that owns them.

**Sign-in and authorization.** When `var.oidc` is set, Grafana's `auth.generic_oauth` is
configured from it, and the platform role convention
([ADR 013](../../adr/013-roles-are-carried-in-the-token.md)) applies with slug `grafana` — so
**two roles are recognised** ([LOCAL-001](adr/LOCAL-001-two-grafana-roles-strict.md)):

| Claim value | Grafana org role | Can |
| --- | --- | --- |
| `GRAFANA_ADMIN` | `Admin` | everything within the org, including datasources and users |
| `GRAFANA_VIEWER` | `Viewer` | read dashboards and explore; change nothing |
| *neither* | — | **not sign in at all** |

They are read from `resource_access.grafana.roles`, overridable by `var.oidc.groups_claim`
when a provider emits them elsewhere. Grafana evaluates `role_attribute_path` as **JMESPath**,
not JSONPath, so the expression carries no `$.` prefix:

```ini
role_attribute_path   = contains(resource_access.grafana.roles[*], 'GRAFANA_ADMIN') && 'Admin' || contains(resource_access.grafana.roles[*], 'GRAFANA_VIEWER') && 'Viewer' || ''
role_attribute_strict = true
```

`role_attribute_strict` is what turns "no role" into a refused login rather than a silent
default. That is [REQ-06](../../requirements.md)'s posture applied to a person instead of a
port: access is an act, not the state you end up in by not being mentioned.

The module **declares** the claim it needs; whether the issuer emits it is that issuer's
business and an operational matter, per the third shared-contract rule in
[the platform spec](../../platform.md#contracts). A token without the claim produces a
refused login, not a broken module.

**The local login form follows `oidc`, and there is no input for it.** `oidc` set means the form
is off, so REQ-01's "one account" is a fact rather than a preference; `oidc` null means the form
is on, because otherwise there would be no way in at all. Two states, derived from one input,
with nothing to configure and nothing to get wrong.

What that leaves when the issuer is down: the form is gone, but Grafana's admin account still
exists in PostgreSQL and still authenticates to the HTTP API with basic auth. That is the
break-glass route — unadvertised rather than absent, and worth knowing before an outage rather
than during one. Its credential comes from `var.admin`, by reference like every other, and the
account is only a route back in if somebody set that value to something they know.

**Grafana must trust the lab's certificate authority, and this is where it is mounted.** Every
server-to-server call to the issuer — discovery, token exchange, userinfo — is made by Grafana's
own HTTP client against a certificate signed by an authority no container trusts by default.
The bundle is already in this namespace
([ADR 018](../../adr/018-one-trust-bundle-for-the-cluster.md));
this module mounts it. Without the mount, OIDC fails on the callback with
`x509: certificate signed by unknown authority`, which reads as a broken OIDC configuration and
is not one.

### Alerting

**Grafana's own, and nothing else** ([LOCAL-003](adr/LOCAL-003-alerting-lives-in-grafana.md)).
Unified Alerting is enabled — it is on by Grafana's own default — and evaluates rules against
whichever datasources exist. Rules, contact points, notification policies and silences are all
authored in the UI and stored in the PostgreSQL this module already requires.

**This module provisions none of them.** No `alerting:` values, no rule files, no contact
points in git. The capability is present and unconfigured, which is a different thing from
absent: nothing fires until somebody has had a reason to make it fire. No separate Alertmanager
is deployed — Grafana embeds one, and a second would be a second place a rule could be
authored.

## Prerequisites

**A PostgreSQL database**, reachable, with a role that owns it
([ADR 008](../../adr/008-postgresql-is-external.md)). Grafana does not start without one and
there is no SQLite fallback.

**Its credential, filled in.** With `database.secret_name` left null the Secret is rendered by
this module — empty, with `username` and `password` present — and its contents are ignored on
every sync ([ADR 022](../../adr/022-secrets-are-rendered-empty.md)). Naming an existing Secret
instead means this module only reads it:

```sh
kubectl patch secret grafana-db-credentials -n observability --type merge -p "$(jq -n \
  --arg u "$(printf %s "$DB_USER" | base64)" \
  --arg p "$(printf %s "$DB_PASSWORD" | base64)" '{data:{username:$u,password:$p}}')"

kubectl rollout restart deployment/grafana -n observability
```

**The admin credential, filled in the same way**, into `grafana-admin-credentials` with keys
`admin-user` and `admin-password`. Grafana does not start without it, and it is the account the
[Access](#access) section names as the break-glass route — so it is worth setting to something
somebody has written down, rather than treating it as a formality:

```sh
kubectl patch secret grafana-admin-credentials -n observability --type merge -p "$(jq -n \
  --arg u "$(printf %s admin | base64)" \
  --arg p "$(printf %s "$ADMIN_PASSWORD" | base64)" '{data:{"admin-user":$u,"admin-password":$p}}')"
```

**The trust bundle ConfigMap**, whenever `oidc` is set — distributed by
[`certificate-management-cert-manager`](../certificate-management-cert-manager/README.md) into
every namespace ([ADR 018](../../adr/018-one-trust-bundle-for-the-cluster.md)). This module mounts
it and does not create it; if it is absent the pod does not start.

**An OIDC client**, registered by hand in the issuer's console with this module's `grafana_url`
as a redirect URI, and the two roles the [Access](#access) section names. Nothing in this
repository declares it ([ADR 013](../../adr/013-roles-are-carried-in-the-token.md)).

## Inputs

```hcl
metrics_url = null    # at least one of the three must be set
logs_url    = null
traces_url  = null

database = {          # required — Grafana's own state
  host_port     = "postgres.example:5432"
  database_name = "grafana"
  secret_name   = null    # null: rendered here, empty, keys in place
}                         # set:  an existing Secret, only read

admin = {}            # the break-glass account; secret_name null renders the placeholder

gateway = null   # exposes Grafana
oidc    = null   # Grafana delegates authentication and authorization when set
metrics = {
  enabled = false   # whether Grafana emits a ServiceMonitor
  tenant  = null    # which tenant its own telemetry is stored under; null: the cluster's own
}

tenants        = ["lab"]   # one datasource per tenant per switched-on signal
default_tenant = "lab"     # whose datasource Grafana marks as the one default

trust_bundle_name = "cert-ca-bundle"   # the ConfigMap to mount; required whenever oidc is set
```

Plus a namespace, the chart version, and a values override.

**`admin` is not one of the shared contracts and carries no value**, only a Secret name and the
two keys inside it — the same two-mode shape as `database.secret_name`. There is no
`admin_password` input and there will not be one: a password in a var file is a credential in
declared configuration, which is the thing this platform does not do.

`gateway`, `oidc` and `database` are the shared contracts, unchanged in shape
([ADR 007](../../adr/007-modules-receive-credentials.md)). `oidc.groups_claim`, when set,
replaces the default claim path for role lookup.

**`metrics.tenant` is written as an `opentelemetry.io/tenant` label on Grafana's Service and on its
pod**, where the collector discovers it and routes both this workload's metrics and its logs
([ADR 025](../../adr/025-a-workload-carries-its-tenant.md)). It is the console's *own* telemetry and
has nothing to do with `tenants` below, which is what datasources are built for. `null` leaves it
unlabelled and stored as the cluster's own.

**The three addresses come from the storage module's outputs**, and each is either a URL or
`null`. They are addresses rather than a copy of that module's three `enable_*` flags on
purpose: a flag and the store it claims to describe are two truths that could disagree, and
every correlation link above would then be wired against a datasource that is not there. Since
[ADR 020](../../adr/020-one-root-module.md) they arrive as `module.<storage>.<output>`, so they
cannot — but an address still says more than a boolean, which is why the shape stands.

**`database` is required, and there is no SQLite fallback.** Grafana's state — users,
preferences, annotations, and now every alert rule — is the only thing in either observability
module that cannot be regenerated from git. Making it required also means Grafana owns no
volume at all. The cost is stated plainly: **Grafana does not start without PostgreSQL**, and
that is this module's one hard external dependency.

**There is no input for the login form.** It follows `oidc` and nothing else — see
[Access](#access). An input existed in an earlier draft, defaulting to a value derived from
`oidc` and overridable in both directions; it was removed because three of its four states were
the derived one restated and the fourth locked everyone out and had to be refused at plan time.
A knob whose only novel setting is invalid is not a knob.

**`default_tenant` must appear in `tenants`**, and is refused at plan time otherwise. Deriving it
from list ordering is the kind of implicit rule that is obvious to whoever wrote it and to nobody
else.

**Exactly one datasource in the file is the default, and Grafana's limit is per organization rather
than per type.** It is the default tenant's metrics datasource — what Explore opens on and what a
panel naming no datasource falls back to — or, where this environment ships no metrics, its logs and
then its traces. Marking one per type instead is `Only one datasource per organization can be marked
as default`, which refuses the whole provisioning file: Grafana then starts with none of the
datasources, not with the ones it did not object to.

## Outputs

| Output | Used by |
| --- | --- |
| `grafana_url` | OIDC client redirect URI registration |
| `database_secret_name` | the operator, to know what to fill in |
| `admin_secret_name` | the same |
| `oidc_secret_name` | the same — `null` unless `oidc` is set |

**One address, and three names.** A console is something people look at; nothing else in the
platform consumes it, which is why there is a single URL. The three Secret names are a different
kind of output: each is either what the caller named or what this module chose, and publishing
the effective value is what stops a caller holding the same fallback expression twice.

## Acceptance criteria

Scenario IDs restart at `CON-01`. The scenarios that came from the module this was split out
of did not keep their `OBS-` numbers, because an ID is never reused for a different assertion
and none of these assert quite what they used to.

```gherkin
Feature: One console over whatever observability is switched on

  @plan
  Scenario: [CON-01] Something must be readable
    Given metrics_url, logs_url and traces_url are all null
    When tofu plan runs
    Then it fails with a validation error naming the three inputs

  @cluster
  Scenario: [CON-02] One address and one tenant, one datasource
    Given only logs_url is set
     And tenants names lab and scratch
    When Grafana's datasources are read
    Then exactly two exist, both of type loki
     And both address the value of logs_url
     And each sends X-Scope-OrgID naming its own tenant

  @cluster
  Scenario: [CON-17] Exactly one datasource is the default
    Given all three addresses are set
     And tenants names lab and scratch
    When Grafana's datasources are read
    Then exactly one has isDefault true
     And it is the metrics datasource of default_tenant

  @cluster
  Scenario: [CON-18] The default follows whichever store is shipped
    Given metrics_url is null and logs_url and traces_url are set
    When Grafana's datasources are read
    Then exactly one has isDefault true
     And it is the logs datasource of default_tenant

  @cluster
  Scenario: [CON-03] Grafana survives metrics being absent
    Given metrics_url is null and logs_url is set
    When the module is applied
    Then Grafana starts and serves its UI

  @cluster
  Scenario: [CON-04] The service graph is wired when both ends exist
    Given metrics_url and traces_url are both set
    When the traces datasource is read
    Then serviceMap.datasourceUid names the metrics datasource

  @cluster
  Scenario: [CON-05] Traces without metrics degrades cleanly
    Given traces_url is set and metrics_url is null
    When the traces datasource is read
    Then serviceMap is unset
     And no Service Graph tab offers a query that cannot be answered

  @cluster
  Scenario: [CON-06] Only Grafana is exposed
    Given a gateway is supplied
    When HTTPRoutes in the namespace are listed
    Then exactly one exists, addressing the Grafana Service

  @cluster
  Scenario Outline: [CON-07] Roles come from the token, and nothing else gets in
    Given an oidc issuer is supplied
    When a person whose token carries <claim> signs in
    Then the result is <outcome>

    Examples:
      | claim              | outcome                          |
      | GRAFANA_ADMIN      | the Admin org role               |
      | GRAFANA_VIEWER     | the Viewer org role              |
      | no recognised role | a refused login, and no account  |

  @plan
  Scenario Outline: [CON-08] Local login follows oidc, and nothing else
    Given oidc is <oidc>
    When tofu plan runs
    Then the login form is <form>
     And no input governs it

    Examples:
      | oidc | form     |
      | null | enabled  |
      | set  | disabled |

  @plan
  Scenario: [CON-12] The default tenant is one of the tenants
    Given default_tenant names a tenant absent from tenants
    When tofu plan runs
    Then it fails, naming both inputs

  @cluster
  Scenario: [CON-13] Grafana trusts the lab authority
    Given oidc is set
    When the Grafana pod is inspected
    Then the trust bundle ConfigMap is mounted into its trust store
     And a request to the issuer's discovery URL from inside the pod succeeds

  @plan
  Scenario: [CON-09] A database is mandatory
    Given database is null
    When tofu plan runs
    Then it fails
     And SQLite is never selected as a fallback

  @cluster
  Scenario: [CON-10] Nothing is provisioned to alert
    Given any combination of addresses
    When the module is applied
    Then Grafana has no provisioned alert rules, contact points or notification policies
     And no Alertmanager workload is running in the namespace

  @cluster
  Scenario: [CON-14] The chart generates no credential of its own
    Given admin.secret_name is null
    When each Application spec is read from the API server
    Then a secret-template Application renders grafana-admin-credentials
     And the grafana chart renders no admin Secret
     And no admin password appears in any rendered Helm values

  @cluster
  Scenario Outline: [CON-15] Every credential follows the same two modes
    Given <input> names <secret_name>
    When Applications in the namespace are listed
    Then a secret-template Application <renders> it

    Examples:
      | input       | secret_name       | renders            |
      | database    | null              | exists rendering   |
      | database    | an existing Secret| does not exist for |
      | admin       | null              | exists rendering   |
      | oidc        | null              | exists rendering   |
      | oidc        | an existing Secret| does not exist for |

  @plan
  Scenario: [CON-16] No credential is an input by value
    Given any configuration
    When the module's variables are read
    Then none of them accepts a password, a secret or a token
     And every credential is named rather than carried

  @cluster
  Scenario: [CON-11] An alert authored in the UI outlives the pod
    Given a person with the Admin role has created an alert rule and a contact point
    When the Grafana pod is deleted and rescheduled
    Then both are still present
     And neither appears in any Application's rendered Helm values
```

## Open items

- **Alerting is authored in a UI and stored in a database, so nothing reviews it.** That is what
  [LOCAL-003](adr/LOCAL-003-alerting-lives-in-grafana.md) bought and it is the price it paid: a
  rule cannot be diffed, cannot be code-reviewed, and arrives in no pull request. Grafana can
  export rules as provisioning YAML — if alerting ever matters, exporting it into git
  periodically is the cheapest way to stop the state being write-only.
- **Losing the PostgreSQL loses alerting as well as Grafana's state.** Users, preferences,
  annotations, every alert rule and every contact point are in one database, none of them
  regenerable from git, and nothing in this repo backs it up
  ([platform scope](../../platform.md#scope)).
- **Nothing evaluates while Grafana is down.** Rules run in Grafana, so the console being
  unavailable and the alerting being unavailable are the same outage. On one operator and two
  nodes that is acceptable; it is also exactly the failure a separate rule evaluator would have
  prevented, which is the trade the ADR made deliberately.
- **With `oidc` set, the only way in when the issuer is down is the admin account over the
  HTTP API.** The form is disabled and the issuer runs in this same cluster, so an issuer outage
  is a console lockout for anyone using a browser. The account behind that route is a static
  credential outside the OIDC path and outside anyone's attention; it needs an owner whether or
  not it is ever used.
- **Datasources multiply with tenants, and nothing prunes them.** Two tenants over three signals
  is six, each with its own correlation wiring. Removing a tenant from `tenants` removes its
  datasources; dashboards pointing at them do not follow.
- **A correlation link cannot cross a tenant.** A trace pushed under one tenant by a workload
  whose logs are tailed into another will never link to them, and the failure is a link that
  quietly returns nothing rather than an error. This is the sharpest consequence of partitioning
  writes and it lands entirely on this module.
- **Nothing checks that `tenants` matches what is actually being written.** A tenant nobody
  writes to shows an empty datasource; a tenant being written to and absent from this list is
  invisible in the console. Both are silent.
- **The trust bundle is a hard dependency of OIDC and is mounted, not verified.** If
  `certificate-management-cert-manager` has not been applied, the ConfigMap is absent and the
  pod does not start — which is the loud failure. If it is present but stale, the pod starts and
  OIDC fails, which is the quiet one.
- **The OIDC endpoints are derived from `issuer_url` by string concatenation.** Grafana's generic
  OAuth wants `auth_url`, `token_url` and `api_url` and reads no discovery document, while the
  contract carries only the issuer — so this module appends the paths itself. They are correct for
  the issuer this platform runs and would be wrong for one that lays its endpoints out
  differently, which makes this the one place the console knows something about *which* issuer it
  is talking to. Swapping the issuer for another product is a values change here, not just at the
  root, and nothing in the module says so at plan time.
- **Three placeholders is three things to fill in before anything works**, in a module that has
  no other manual step. Two of them lock Grafana out entirely if forgotten — no database, no
  admin — and the third only breaks sign-in. Nothing distinguishes them at sync time; all three
  come up healthy and empty.
- **No dashboards ship.** Import by `gnetId` through the chart, or accept a blank Grafana on
  day one.
