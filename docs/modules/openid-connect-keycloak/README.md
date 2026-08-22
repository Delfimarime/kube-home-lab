# Module: openid-connect-keycloak

**Status:** draft ·
**Satisfies:** [REQ-01, REQ-09, REQ-10](../../requirements.md) ·
**Decisions:** [LOCAL-001](adr/LOCAL-001-oidc-provider-keycloak.md),
[LOCAL-002](adr/LOCAL-002-the-operator-comes-from-upstream-manifests.md),
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
| 0 | `keycloak-operator` | upstream's kustomization, at a git tag | the CRDs and the controller |
| 1 | `keycloak` | `keycloak-instance` — authored by this repo | the `Keycloak` resource and its route |

**An operator without an instance is not an identity provider**, which is why both ship here
rather than the operator being a prerequisite. The waves exist because the `Keycloak` CRD has to
be installed before anything declares one, and `ServerSideApply=true` is set on wave 0 for the
same annotation-size reason the other CRD bundles need it.

**Wave 0 is the one element here that is not a chart.** The operator is published as manifests
and an OLM bundle, so this module points an `Application` at upstream's kustomization and the git
tag is the pin ([LOCAL-002](adr/LOCAL-002-the-operator-comes-from-upstream-manifests.md)). The
operator's tag and the server image on the `Keycloak` resource are versioned together upstream
and move as a pair.

**`keycloak-instance` is the custom case** of
[ADR 010](../../adr/010-resources-delivered-via-chart.md) — there is no upstream chart that
renders a `Keycloak` resource the way this platform wants one. It renders:

- the `Keycloak` resource: one replica, the supplied database, the bootstrap admin from an
  existing Secret
- **`spec.hostname.hostname` is a full URL, not a hostname** — `https://<var.gateway.hostname>`.
  The field takes either, and the bare form leaves Keycloak resolving scheme and port from
  request headers on every call. Behind a Gateway that terminates TLS at 443 and speaks HTTP
  onward, that is the difference between an issuer that is fixed and one that is whatever the
  last proxy claimed. **The same string builds `issuer_url`**, so the discovery document and this
  module's output cannot disagree — which is what makes `OIDC-03` a check rather than a hope.
- **HTTP, not HTTPS, inside the cluster.** TLS terminates at the Gateway, so the instance runs
  with `http.httpEnabled` and `proxy.headers: xforwarded`. **The second changes no URL this
  module publishes** — the full-URL hostname above already fixes those, which is the point of
  writing it that way. What it buys is the `X-Forwarded-For` that Traefik sets on every routed
  request: with the field unset the operator falls back to `proxy=passthrough`, and every login
  event is then recorded against the Traefik pod's address rather than the client's. For an
  issuer that is the one field in an event log worth having. It is given no certificate, which
  means it needs no trust material and holds none.
- **No backchannel split.** `hostname.backchannelDynamic` stays at its default of false, so a
  consumer reaches this issuer on the same external hostname a browser does — which is the choice
  [LOCAL-001](adr/LOCAL-001-oidc-provider-keycloak.md) made, and the field that implements it.
- the operator's own `Ingress` **disabled**, and one `HTTPRoute` rendered from `var.gateway`
  instead. Gateway API is the platform's ingress
  ([README § Assumptions](../../../README.md#assumptions)) and the operator does not speak it,
  so exactly one path in exists and this chart owns it.

**Scraping is the operator's, not this chart's.** The `Keycloak` resource carries
`spec.serviceMonitor`, so the instance chart renders no `ServiceMonitor` of its own — it sets a
field ([ADR 004](../../adr/004-scrape-config-via-prometheus-crds.md),
[ADR 016](../../adr/016-metrics-is-the-fourth-input.md)). **The field defaults to `true`**, which
is the dangerous direction: on a cluster with no Prometheus CRDs an unset value fails the sync, so
this module writes `metrics.enabled` into it explicitly and never omits it.

**The tenant label reaches the Service and not the pods**, which is the one place this module
cannot do what [ADR 025](../../adr/025-a-workload-carries-its-tenant.md) asks. `spec.serviceMonitor.labels`
lands on the Service, so metrics are attributed. The CR exposes no pod-label field — only
`spec.unsupported.podTemplate` — so logs, which are discovered from pods and never see a Service,
are collected as the cluster's own tenant. Every other module here labels both; this one labels
what it can and the gap is in logs.

## Prerequisites

Two Secrets, each **rendered empty by this module unless it was given one**, and filled by hand,
per environment ([ADR 022](../../adr/022-secrets-are-rendered-empty.md)). Where a name is not
supplied the object arrives with the sync carrying the right keys and no values, and Argo CD
ignores its contents from then on; where one is, this module only reads it. A PostgreSQL database
exists already ([ADR 008](../../adr/008-postgresql-is-external.md)).

```sh
# The database this instance stores its realm, users and sessions in.
kubectl patch secret keycloak-db -n security --type merge -p "$(jq -n \
  --arg u "$(printf %s "$DB_USER" | base64)" \
  --arg p "$(printf %s "$DB_PASSWORD" | base64)" '{data:{username:$u,password:$p}}')"

# The first administrator, used once to sign in and create the realm.
kubectl patch secret keycloak-bootstrap-admin -n security --type merge -p "$(jq -n \
  --arg u "$(printf %s "$ADMIN_USER" | base64)" \
  --arg p "$(printf %s "$ADMIN_PASSWORD" | base64)" '{data:{username:$u,password:$p}}')"

kubectl rollout restart statefulset/keycloak -n security
```

Until both are filled, Keycloak starts and fails to reach its database. The restart afterwards is
required — the values are read at start and do not reload.

The bootstrap admin is a static credential outside the OIDC path and outside anyone's
attention. It is also the only way back in if the realm's configuration breaks, which is why it
is not deleted after first use — and why it needs an owner.

**A sync wave advances on health, and Argo CD has no built-in health check for the `Keycloak`
kind.** Without one it reports the resource healthy as soon as it is applied, so wave 1 completes
while Keycloak is still starting and its database migrations are still running. Nothing here
breaks — this module has no wave 2 — but an environment that adds one, or that reads sync status
to decide anything, wants a `resource.customizations.health.k8s.keycloak.org_Keycloak` entry in
`argocd-cm` reading the CR's `Ready` condition. Argo CD is a per-environment prerequisite this
repo never provisions ([§1.1](../../../CONSTITUTION.md)), so that entry is the environment's to
add.

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

bootstrap_admin_secret_name = null   # null: rendered here, empty, keys in place
                                     # set:  an existing Secret, only read

metrics = { enabled = false, tenant = "security" }   # derived at the root — ADR 024, ADR 025
```

**The realm is not an input, and `master` is why.** Keycloak ships exactly one realm and this
module creates none — the survey in [Open items](#open-items) is why it cannot — so there is one
correct value, and an input for it would be a knob with a single setting. That is the same
reasoning that makes a module's chart path a constant rather than a variable. It lives in one
local, and `issuer_url` is built from it.

**The cost is worth stating rather than hiding.** `master` administers Keycloak, so an
environment signing its people in there has put its users in the realm that governs the server.
An environment that minds creates a second realm in the console — and that is the day this
constant becomes an input, because `issuer_url` has to move with it. Consumers read the realm
through `issuer_url` and never name it separately.

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
- **Declaring the realm was surveyed on 2026-08-22 against Keycloak 26.7.2, and not taken.**
  Four mechanisms exist and none of them reconciles a realm:

  | Mechanism | Covers | Reconciles |
  | --- | --- | --- |
  | `KeycloakRealmImport`, `k8s.keycloak.org` — ships with the operator | realm, clients, roles, groups | **no** — created once, later edits to the CR are ignored |
  | `KeycloakRealm`, in the `keycloak-realm-operator` side-car | realm | **no** — its own README says updates to the CR are ignored |
  | `KeycloakOIDCClient` / `KeycloakSAMLClient`, `k8s.keycloak.org/v2alpha1`, Keycloak 26.7+ | clients only | yes, by polling |
  | `keycloak-config-cli`, a third-party Job | realm, clients, roles, groups | yes, idempotently |

  **The client CRDs are the ones that look like the answer and are not.** They carry an explicit
  *do not use in production* banner, sit at `v2alpha1`, need the `client-admin-api:v2` feature
  flag on the server, and — decisively — there is no role or group CRD beside them, so
  [ADR 013](../../adr/013-roles-are-carried-in-the-token.md)'s `<SLUG>_ADMIN`/`<SLUG>_VIEWER`
  still could not be declared. Clients without roles buys the `client_id` wiring and derived
  redirect URIs while leaving the whole role model in the console, on an experimental CRD, on the
  identity path.

  **The credential seam is resolved, and it favours generation.** Realm settings, clients, client
  roles, groups and their role mappings are all safe to declare — none is a credential. Client
  *secrets* are not, at either exposure: the values reaching an `Application` spec in etcd, which
  `OIDC-06` checks, and the resource those values render into. Left undeclared, Keycloak mints
  the secret and a person copies it once into the consumer's Secret. Declared, [§5.2](../../../CONSTITUTION.md)
  applies — a Secret is namespaced, so the issuer's namespace and the consumer's each hold a
  placeholder and a person fills **both**. Generation costs one typing and declaration costs two,
  so the mechanism that reads a `secretRef` is the more expensive one to operate as well as the
  less capable one.

  What this repository would gain is a *record* ([REQ-11](../../requirements.md)) and not a
  reconciled resource ([REQ-08](../../requirements.md)) — and, more usefully, three strings that
  stop being typed by hand: a consumer's `client_id`, its role names, and its redirect URI, all of
  which the root module could derive from values it already holds. That is worth revisiting when
  a role or group CRD lands, when the client CRDs leave experimental, or at
  [LOCAL-001](adr/LOCAL-001-oidc-provider-keycloak.md)'s roughly fifteen clients — whichever
  arrives first. Taking `keycloak-config-cli` before then buys reconciliation at the cost of a
  dependency version-matched to the Keycloak major and of promoting the bootstrap admin from
  break-glass to load-bearing.
- **`<slug>` and `client_id` must be the same string and nothing checks it.** Keycloak keys
  `resource_access` by client ID. A mismatch is a refused login that reads as a broken module.
  A validation comparing them cannot live here — this module never sees a consumer's slug — so
  it belongs in each consumer, or in prose.
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
