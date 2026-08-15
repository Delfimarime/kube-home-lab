# Module: observability-console-grafana

**Status:** draft ·
**Satisfies:** [REQ-01, REQ-03, REQ-06, REQ-13](../../requirements.md) ·
**Decisions:** [LOCAL-001](adr/LOCAL-001-two-grafana-roles-strict.md),
[LOCAL-003](adr/LOCAL-003-alerting-lives-in-grafana.md),
[ADR 005](../../adr/005-modules-are-applicationsets.md),
[ADR 007](../../adr/007-modules-receive-credentials.md),
[ADR 010](../../adr/010-resources-delivered-via-chart.md),
[ADR 013](../../adr/013-roles-are-carried-in-the-token.md)

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
`List` generator produces one Application — one static entry, as that ADR requires even at one:

| Wave | Application | Chart | Condition |
| --- | --- | --- | --- |
| 0 | `grafana` | `grafana` (grafana-community) | always |

**Datasources are generated from the three address inputs**, one per address that is not
`null`. Their *types* are not inputs: an address named `metrics_url` becomes a `prometheus`
datasource, `logs_url` a `loki` one, `traces_url` a `tempo` one. Swapping the store behind a
capability ([REQ-09](../../requirements.md)) means swapping it for something speaking the same
query API, so a type input would be flexibility nobody would ever spend.

### Correlation

The reason for choosing this stack. **Each link is conditional on both of its ends existing**,
and both ends are simply two of the three addresses being non-null:

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
[the platform spec](../../platform.md#shared-contracts). A token without the claim produces a
refused login, not a broken module.

**The local login form follows `oidc`, and can be overridden.** `allow_local_login` defaults to
`null`, which means *derive it*: the form is on when `oidc` is `null` — otherwise there would be
no way in at all — and off once an issuer is wired, so that REQ-01's "one account" is a fact
rather than a preference. Setting it to `true` alongside `oidc` keeps the form as a break-glass
route for when the issuer is down; setting it to `false` with no `oidc` locks everyone out and
is refused at plan time.

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

## Inputs

```hcl
metrics_url = null    # at least one of the three must be set
logs_url    = null
traces_url  = null

database = {          # required — Grafana's own state
  host_port     = "postgres.example:5432"
  database_name = "grafana"
  secret_name   = "grafana-db"
}

gateway = null   # exposes Grafana
oidc    = null   # Grafana delegates authentication and authorization when set

allow_local_login = null   # null follows oidc — see below
```

Plus a namespace, the chart version, and a values override.

`gateway`, `oidc` and `database` are the shared contracts, unchanged in shape
([ADR 007](../../adr/007-modules-receive-credentials.md)). `oidc.groups_claim`, when set,
replaces the default claim path for role lookup.

**The three addresses come from the storage module's outputs**, and each is either a URL or
`null`. They are addresses rather than a copy of that module's three `enable_*` flags on
purpose: a flag and the store it claims to describe are two truths that can disagree once they
live in different units, and every correlation link above would then be wired against a
datasource that is not there.

**`database` is required, and there is no SQLite fallback.** Grafana's state — users,
preferences, annotations, and now every alert rule — is the only thing in either observability
module that cannot be regenerated from git. Making it required also means Grafana owns no
volume at all. The cost is stated plainly: **Grafana does not start without PostgreSQL**, and
that is this module's one hard external dependency.

**`allow_local_login` is the only input with a derived default**, because the safe value depends
on another input:

| `oidc` | `allow_local_login` | Grafana's login form |
| --- | --- | --- |
| `null` | `null` | **on** — it is the only way in |
| set | `null` | **off** — one account per environment, as REQ-01 asks |
| set | `true` | **on** — deliberate break-glass, kept for when the issuer is down |
| `null` | `false` | rejected at plan time: nobody could sign in |

## Outputs

| Output | Used by |
| --- | --- |
| `grafana_url` | OIDC client redirect URI registration |

One, and the point is how few. A console is something people look at; nothing else in the
platform consumes it.

## Acceptance criteria

Scenario IDs restart at `CON-01`. The scenarios that came from the module this was split out
of did not keep their `OBS-` numbers, because an ID is never reused for a different assertion
and none of these assert quite what they used to.

```gherkin
Feature: One console over whatever observability is switched on

  @plan
  Scenario: [CON-01] Something must be readable
    Given metrics_url, logs_url and traces_url are all null
    When terraform plan runs
    Then it fails with a validation error naming the three inputs

  @cluster
  Scenario: [CON-02] One address, one datasource
    Given only logs_url is set
    When Grafana's datasources are read
    Then exactly one exists, of type loki
     And it addresses the value of logs_url

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
  Scenario Outline: [CON-08] Local login follows oidc, and cannot lock everyone out
    Given oidc is <oidc> and allow_local_login is <override>
    When terraform plan runs
    Then <outcome>

    Examples:
      | oidc | override | outcome                             |
      | null | null     | the login form is enabled           |
      | set  | null     | the login form is disabled          |
      | set  | true     | the login form is enabled           |
      | null | false    | the plan fails, naming both inputs  |

  @plan
  Scenario: [CON-09] A database is mandatory
    Given database is null
    When terraform plan runs
    Then it fails
     And SQLite is never selected as a fallback

  @cluster
  Scenario: [CON-10] Nothing is provisioned to alert
    Given any combination of addresses
    When the module is applied
    Then Grafana has no provisioned alert rules, contact points or notification policies
     And no Alertmanager workload is running in the namespace

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
- **Losing the PostgreSQL now loses alerting too.** It already held the only non-regenerable
  state; it now holds every rule and contact point as well. Nothing in this repo backs it up
  ([platform scope](../../platform.md#scope)), and the consequence just got larger.
- **Nothing evaluates while Grafana is down.** Rules run in Grafana, so the console being
  unavailable and the alerting being unavailable are the same outage. On one operator and two
  nodes that is acceptable; it is also exactly the failure a separate rule evaluator would have
  prevented, which is the trade the ADR made deliberately.
- **`allow_local_login = true` is a password nobody will rotate.** The break-glass route is
  worth having when the issuer runs in this same cluster, but the account it keeps alive is a
  static credential outside the OIDC path and outside anyone's attention. If it is switched on,
  it needs an owner.
- **No dashboards ship.** Import by `gnetId` through the chart, or accept a blank Grafana on
  day one.
