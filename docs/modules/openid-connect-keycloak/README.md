# Module: openid-connect-keycloak

**Status:** draft ·
**Satisfies:** [REQ-01, REQ-09, REQ-10](../../requirements.md) ·
**Decisions:** [LOCAL-001](adr/LOCAL-001-oidc-provider-keycloak.md),
[ADR 005](../../adr/005-modules-are-applicationsets.md),
[ADR 007](../../adr/007-modules-receive-credentials.md),
[ADR 008](../../adr/008-postgresql-is-external.md),
[ADR 010](../../adr/010-resources-delivered-via-chart.md),
[ADR 011](../../adr/011-environments-are-clusters.md),
[ADR 013](../../adr/013-roles-are-carried-in-the-token.md),
[ADR 016](../../adr/016-metrics-is-the-fourth-input.md),
[ADR 022](../../adr/022-secrets-are-rendered-empty.md)

## Intent

Run one OIDC issuer for the environment, and publish its address. Nothing more.

One issuer *per environment* — each cluster runs its own
([ADR 011](../../adr/011-environments-are-clusters.md)), so accounts do not carry between them.

The module does not know which services authenticate against it, does not register clients, and
does not hold client secrets. Those are registered by hand and delivered to consumers as Secret
references ([ADR 007](../../adr/007-modules-receive-credentials.md)).

**It also does not define roles.** [ADR 013](../../adr/013-roles-are-carried-in-the-token.md)
fixes the shape a role arrives in; which roles exist, and who holds them, is realm configuration
created in Keycloak's console — see [Open items](#open-items), because that is the largest thing
this module does not do.

## Provisions

One Argo CD `ApplicationSet` ([ADR 005](../../adr/005-modules-are-applicationsets.md)), whose
`List` generator produces two Applications:

| Wave | Application | Chart | Provides |
| --- | --- | --- | --- |
| 0 | `keycloak-operator` | the Keycloak Operator | the CRDs and the controller |
| 1 | `keycloak` | `keycloak-instance` — authored by this repo | the `Keycloak` resource and its route |

**An operator without an instance is not an identity provider**, which is why both ship here
rather than the operator being a prerequisite. The waves exist because the `Keycloak` CRD has to
be installed before anything declares one, and `ServerSideApply=true` is set on wave 0 for the
same annotation-size reason the other CRD bundles need it.

**`keycloak-instance` is the custom case** of
[ADR 010](../../adr/010-resources-delivered-via-chart.md) — there is no upstream chart that
renders a `Keycloak` resource the way this platform wants one. It renders:

- the `Keycloak` resource: one replica, the supplied database, the bootstrap admin from an
  existing Secret, `hostname` from `var.gateway.hostname`
- **HTTP, not HTTPS, inside the cluster.** TLS terminates at the Gateway, so the instance runs
  with `http.httpEnabled` and trusts forwarded headers. It is given no certificate, which means
  it needs no trust material and holds none.
- the operator's own `Ingress` **disabled**, and one `HTTPRoute` rendered from `var.gateway`
  instead. Gateway API is the platform's ingress
  ([README § Assumptions](../../../README.md#assumptions)) and the operator does not speak it,
  so exactly one path in exists and this chart owns it.

**Scraping.** When `metrics.enabled` is `true`, the instance's management interface exposes
metrics and a `ServiceMonitor` is rendered
([ADR 004](../../adr/004-scrape-config-via-prometheus-crds.md),
[ADR 016](../../adr/016-metrics-is-the-fourth-input.md)).

## Prerequisites

Two Secrets, each **rendered empty by this module unless it was given one**, and filled by hand,
per environment ([ADR 022](../../adr/022-secrets-are-rendered-empty.md)). Where a name is not
supplied the object arrives with the sync carrying the right keys and no values, and Argo CD
ignores its contents from then on; where one is, this module only reads it. A PostgreSQL database
exists already ([ADR 008](../../adr/008-postgresql-is-external.md)).

```sh
# The database this instance stores its realm, users and sessions in.
kubectl patch secret keycloak-db -n identity --type merge -p "$(jq -n \
  --arg u "$(printf %s "$DB_USER" | base64)" \
  --arg p "$(printf %s "$DB_PASSWORD" | base64)" '{data:{username:$u,password:$p}}')"

# The first administrator, used once to sign in and create the realm.
kubectl patch secret keycloak-bootstrap-admin -n identity --type merge -p "$(jq -n \
  --arg u "$(printf %s "$ADMIN_USER" | base64)" \
  --arg p "$(printf %s "$ADMIN_PASSWORD" | base64)" '{data:{username:$u,password:$p}}')"

kubectl rollout restart statefulset/keycloak -n identity
```

Until both are filled, Keycloak starts and fails to reach its database. The restart afterwards is
required — the values are read at start and do not reload.

The bootstrap admin is a static credential outside the OIDC path and outside anyone's
attention. It is also the only way back in if the realm's configuration breaks, which is why it
is not deleted after first use — and why it needs an owner.

## Inputs

```hcl
database = {            # required
  host_port     = "postgresql.storage.svc.cluster.local:5432"
  database_name = "keycloak"
  secret_name   = null    # null renders it here, empty; set names an existing one
  username_key  = "username"
  password_key  = "password"
  sslmode       = "require"
}

gateway = {             # required in practice: an unreachable issuer is useless
  name         = "traefik"
  namespace    = "kube-system"
  hostname     = "id.lab.internal"
  section_name = "web-tls"
}

realm = "lab"

bootstrap_admin_secret_name = null   # null: rendered here, empty, keys in place
                                     # set:  an existing Secret, only read

metrics = { enabled = false }   # a root variable, declared once — ADR 016
```

**`realm` is an input with no useful default.** Keycloak's `master` realm administers Keycloak;
signing people in from it means the administrative realm and the environment's realm are the
same one. Consumers read the realm through `issuer_url` and never name it separately.

**`gateway.section_name` names the ordinary TLS listener.** The mTLS listener exists for the
OTLP ingest endpoint and a browser cannot present a client certificate
([certificate-management-cert-manager](../certificate-management-cert-manager/README.md)).

## Outputs

| Output | Value |
| --- | --- |
| `issuer_url` | `https://<hostname>/realms/<realm>` |
| `discovery_url` | `https://<hostname>/realms/<realm>/.well-known/openid-configuration` |

There is deliberately no client output. See
[ADR 007](../../adr/007-modules-receive-credentials.md).

**The realm is in the address**, which is a change in shape rather than in meaning — a consumer
still receives one URL and never assembles it. Both reach a consumer's `oidc` input as
`module.<this>.issuer_url` in the root module ([ADR 020](../../adr/020-one-root-module.md)).

## Acceptance criteria

`OIDC-05` is retired: it asserted that a masterkey never reached a rendered value, and this
implementation has no masterkey. The number is not reused.

```gherkin
Feature: An issuer, and only an issuer

  @plan
  Scenario: [OIDC-01] The module publishes no client material
    Given the module has been applied
    When its outputs are enumerated
    Then none is named for a client
     And no output is marked sensitive because none carries a secret

  @plan
  Scenario: [OIDC-02] A database is mandatory
    Given database is null
    When tofu plan runs
    Then it fails

  @cluster
  Scenario: [OIDC-03] The published issuer is the real one
    Given the module has been applied with a gateway
    When the discovery document is fetched from discovery_url
    Then its "issuer" field equals the issuer_url output

  @cluster
  Scenario: [OIDC-04] One replica
    Given the module has been applied
    When the Keycloak resource is inspected
    Then it declares exactly one instance

  @cluster
  Scenario: [OIDC-06] No credential is rendered into an Application
    Given a database and a bootstrap admin Secret are supplied
    When each Argo CD Application spec is read from the API server
    Then both are referenced by name
     And neither password appears in any rendered Helm values

  @cluster
  Scenario: [OIDC-07] There is exactly one path in
    Given a gateway is supplied
    When HTTPRoutes and Ingresses in the namespace are listed
    Then exactly one HTTPRoute exists, addressing the Keycloak Service
     And no Ingress exists
```

## Open items

- **The realm is created and configured by hand, and lives nowhere.** Clients, their redirect
  URIs, the `<SLUG>_ADMIN`/`<SLUG>_VIEWER` roles
  ([ADR 013](../../adr/013-roles-are-carried-in-the-token.md)) and every grant are typed into a
  console, per environment, and again after a rebuild that loses the database. Nothing in this
  repository records what they should be. **This is the largest gap in the platform**, and it is
  larger than the Secrets gap because a forgotten Secret can be retyped from a password manager
  while a forgotten role model cannot be retyped from anything.
- **`KeycloakRealmImport` is a partial fix, and its name misleads.** It imports nothing that
  already exists elsewhere: the realm representation is carried inline in the resource, so using
  it means *authoring* a realm as data. No existing realm is needed — but hand-writing a realm
  representation is unpleasant enough that the real workflow is to build it in the console,
  export it, and commit the export. Which is why nothing is lost by starting in the console.
  Two things to know before taking it up. **It applies, it does not reconcile**: the operator
  runs an import Job on create and update, and console changes afterwards are neither reverted
  nor detected — so it would give a recoverable *record* of the realm
  ([REQ-11](../../requirements.md)) and not a reconciled resource
  ([REQ-08](../../requirements.md)). And **an export embeds client secrets**, which
  [REQ-05](../../requirements.md) forbids reaching a rendered `Application`. Clients and roles
  declared, secrets generated by Keycloak and read back into the Secret each consumer's
  `oidc.secret_name` references, is the seam that looks right and has not been designed.
- **`<slug>` and `client_id` must be the same string and nothing checks it.** Keycloak keys
  `resource_access` by client ID. A mismatch is a refused login that reads as a broken module.
  A validation comparing them cannot live here — this module never sees a consumer's slug — so
  it belongs in each consumer, or in prose.
- **Chart sourcing for the operator is unsettled.** The Keycloak project publishes the operator
  as manifests and an OLM bundle rather than as a chart this repo can pin exactly
  ([ADR 010](../../adr/010-resources-delivered-via-chart.md)). Either a community chart is
  adopted and pinned, or wave 0 becomes a second locally-authored chart wrapping the published
  manifests.
- **Install runs database migrations on start.** Expect one round of sync-ordering trouble on
  first apply, and on any version bump that changes the schema; `ServerSideApply=true` on the
  instance Application may be needed too.
- **The bootstrap admin is a password nobody will rotate.** It is the break-glass route for when
  the realm is misconfigured, and it is a static credential outside the OIDC path. If it is kept
  — and it should be — it needs an owner.
- **Registering clients by hand means redirect URIs are typed by a human**, once per
  environment. Hostnames are one root variable so both sides read the same value
  ([ADR 020](../../adr/020-one-root-module.md)).
- **Revisit at roughly fifteen clients**: a dedicated registration module would not change this
  module's contract, only add a sibling.
