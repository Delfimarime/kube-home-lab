# Module: access-proxy-ory-oathkeeper

**Status:** draft ·
**Satisfies:** [REQ-05, REQ-06, REQ-08, REQ-09, REQ-13](../../requirements.md) ·
**Decisions:** [LOCAL-001](adr/LOCAL-001-the-proxy-is-ory-oathkeeper.md),
[ADR 005](../../adr/005-modules-are-applicationsets.md),
[ADR 007](../../adr/007-modules-receive-credentials.md),
[ADR 010](../../adr/010-resources-delivered-via-chart.md),
[ADR 014](../../adr/014-exposed-does-not-mean-authorized.md),
[ADR 016](../../adr/016-metrics-is-the-fourth-input.md),
[ADR 026](../../adr/026-roles-decide-the-operation-relationships-decide-the-resource.md),
[ADR 027](../../adr/027-a-machine-caller-is-authorized-by-scope.md)

## Intent

**Authenticate a request before it reaches a workload that cannot authenticate it itself.** The
Gateway routes to this module; this module validates the caller's token against the environment's
issuer and forwards only what passes.

It protects **whatever it is told to protect**. The set of surfaces is an input, so adding a second
one is a change where modules are composed rather than a change here
([LOCAL-001](adr/LOCAL-001-the-proxy-is-ory-oathkeeper.md)). Today the set has one member — the
relationship store's write API, which has no authentication of its own
([`resource-authorization-ory-keto`](../resource-authorization-ory-keto/README.md)).

**It authorizes machines, not people.** Callers present a token from the client credentials grant
and are authorized by scope and audience
([ADR 027](../../adr/027-a-machine-caller-is-authorized-by-scope.md)); a person signing in to a
service is [ADR 013](../../adr/013-roles-are-carried-in-the-token.md)'s business and does not come
through here.

## Provisions

One `ApplicationSet` ([ADR 005](../../adr/005-modules-are-applicationsets.md)) with a `List`
generator, holding:

| Application | Chart | Case |
| --- | --- | --- |
| the proxy and its rules | Ory's `oathkeeper` chart, pinned, wrapped by a local chart adding the route | wrapped |

**The rules are rendered with the deployment**, as a ConfigMap the proxy reads — so the boundary
this module enforces is declared in the repository and reconciled, rather than applied to a running
proxy afterwards ([REQ-08](../../requirements.md)).

Two ports, and only one of them is routed:

| Port | Serves | Routed |
| --- | --- | --- |
| proxy | the protected surfaces | yes, through the Gateway |
| api | the rule set and health | **no** |

The api port is deliberately unrouted: it describes every boundary this module enforces, and
publishing that is publishing the map.

### What a rule is

One entry per protected surface. Each carries its own upstream, its own match, and its own token
requirements — none of it global:

```yaml
- id: keto-write
  upstream:
    url: http://keto-write.security.svc.cluster.local:4467
  match:
    url: https://authz.lab.internal/relation-tuples<.*>
    methods: [PUT, PATCH, DELETE]
  authenticators:
    - handler: jwt
      config:
        jwks_urls: [https://sso.lab.internal/realms/lab/protocol/openid-connect/certs]
        trusted_issuers: [https://sso.lab.internal/realms/lab]
        target_audience: [keto]
        required_scope: [keto:write]
        allowed_algorithms: [RS256]
  authorizer: { handler: allow }
  mutators: [{ handler: noop }]
  errors: [{ handler: json }]
```

**The authorizer is `allow` because the authenticator has already decided.** Issuer, audience and
scope are all checked there; there is nothing left for an authorizer to add that this module can
express ([LOCAL-001](adr/LOCAL-001-the-proxy-is-ory-oathkeeper.md) records what it would cost to
go further).

**Methods are part of the boundary, not a detail.** A rule matching the write path without naming
its methods forwards reads to the write port too.

## Prerequisites

**An OIDC client per caller**, registered by hand in the issuer with the client credentials grant
enabled ([ADR 007](../../adr/007-modules-receive-credentials.md)). Nothing in this repository
declares it. Each needs two things the rules then check:

- a **client scope** named for what it may do — `keto:write`;
- an **audience** mapper naming the service — `keto`.

A caller with a valid token and neither of these is refused, which is correct and looks identical
to a broken proxy the first time it happens.

**The issuer reachable from this pod**, for JWKS. The keys are fetched, not configured — an issuer
that cannot be reached means every request is refused.

**The trust bundle ConfigMap**, distributed by
[`certificate-management-cert-manager`](../certificate-management-cert-manager/README.md)
([ADR 018](../../adr/018-one-trust-bundle-for-the-cluster.md)). The issuer is served with a
certificate from an authority this repository owns, so without the bundle the JWKS fetch fails
verification.

**A Gateway with a listener for this hostname.** This module renders a route and does not configure
a listener; what a listener demands of a caller is the Gateway's business and not this module's
([ADR 014](../../adr/014-exposed-does-not-mean-authorized.md)).

**No Secret.** This module holds no credential: it validates tokens with public keys and forwards
to an upstream that requires none.

## Inputs

```hcl
namespace = "security"

gateway = {
  hostname     = "authz.lab.internal"
  name         = "traefik"
  namespace    = "networking"
  section_name = "https"
}

oidc = {
  issuer_url = module.identity.issuer_url
}

# One entry per protected surface. Each is a rule.
services = {
  keto_write = {
    upstream_url   = module.resource_authorization.write_url
    match_path     = "/relation-tuples"
    methods        = ["PUT", "PATCH", "DELETE"]
    audience       = "keto"
    required_scope = ["keto:write"]
  }
}

metrics = { enabled = true, tenant = "security" }
```

**`services` is a map and is deliberately empty-able.** A proxy protecting nothing renders a route
that refuses everything, which is the correct state for an environment that has not wired a
consumer yet.

**`oidc` here carries only an issuer.** Unlike the contract's usual shape it needs no client id and
no Secret — this module validates tokens rather than obtaining them, so it takes the fields it
reads and no others ([§3.4](../../../CONSTITUTION.md#3-module-inputs)).

**`upstream_url` is passed in, never derived.** This module does not know what a relationship store
is; it forwards to an address ([§4.2](../../../CONSTITUTION.md#4-composition)).

Plus two inputs no environment normally writes: `oathkeeper.chart_version`, the pin — and the only
place that version is written, since a value set at the root would not add a second opinion but
replace this one silently; and `argocd.namespace`, where the `ApplicationSet` object goes, together
with `git_repository` — this repository and the revision Argo CD reads its charts at, which every
module rendering one of them takes. This module renders one, so it is always consulted.

## Outputs

| Output | Used by |
| --- | --- |
| `proxy_url` | callers, as the address protected surfaces are reached at |
| `selector` | the module whose port this one is permitted to reach, as its `write_access_from` |

**`selector` is what joins the two halves.** The store restricts its write port to a selector its
caller supplies, and this is the selector to supply — published rather than restated, so nobody
holds the same label expression twice.

## Acceptance criteria

Scenario IDs are `PROXY-NN`.

```gherkin
Feature: A request is authenticated before it reaches what it asks for

  @plan
  Scenario: [PROXY-01] One ApplicationSet, never a bare Application
    Given the module is planned
    When the rendered resources are read
    Then exactly one ApplicationSet is created
     And it uses a List generator
     And no bare Application is created

  @plan
  Scenario: [PROXY-02] Every service becomes exactly one rule
    Given services names two entries
    When the rendered rule set is read
    Then it contains two rules
     And each names its own upstream, audience and required scope

  @plan
  Scenario: [PROXY-03] A rule carries its methods
    Given a service names PUT, PATCH and DELETE
    When the rendered rule set is read
    Then that rule matches those three methods
     And it does not match GET

  @plan
  Scenario: [PROXY-04] The issuer is trusted explicitly
    Given oidc.issuer_url is set
    When the rendered rule set is read
    Then every rule names that issuer in trusted_issuers
     And every rule names a JWKS URL derived from it

  @plan
  Scenario: [PROXY-05] A rule without an audience is refused
    Given a service entry omits audience
    When the module is planned
    Then the plan is refused with a message naming that entry

  @plan
  Scenario: [PROXY-06] Only the proxy port is routed
    Given a gateway is set
    When the rendered HTTPRoute is read
    Then it addresses the proxy port
     And no route addresses the api port

  @plan
  Scenario: [PROXY-07] Nothing sensitive is rendered
    Given the module is planned
    When the rendered Helm values are read
    Then no client secret appears in them
     And no Secret is created by this module

  @cluster
  Scenario: [PROXY-08] A caller with the right scope and audience gets through
    Given a client credentials token carrying scope keto:write and audience keto
    When it writes a relation tuple through the proxy
    Then the write succeeds

  @cluster
  Scenario: [PROXY-09] A valid token with the wrong scope is refused
    Given a client credentials token from the same issuer carrying no keto:write scope
    When it writes a relation tuple through the proxy
    Then the request is refused
     And the upstream never received it

  @cluster
  Scenario: [PROXY-10] A token minted for another service is refused
    Given a token whose audience names a different service
    When it writes a relation tuple through the proxy
    Then the request is refused

  @cluster
  Scenario: [PROXY-11] No token is refused
    Given no Authorization header
    When a relation tuple is written through the proxy
    Then the request is refused

  @cluster
  Scenario: [PROXY-12] A read method on a write route does not pass
    Given a valid token carrying keto:write
    When it issues a GET against the write route
    Then no rule matches and the request is refused
```

## Open items

- **A too-broad rule looks exactly like a correct one.** A match pattern reaching further than
  intended, a missing `target_audience`, a method list that is wider than the surface — each
  forwards requests nobody authorized and produces no error. `PROXY-02` through `PROXY-06` assert
  the shape of what is rendered, which catches the mistakes that are visible in a plan and not the
  ones that are only visible in what a rule *permits*. There is no negative test for "matches
  nothing else"; writing one means enumerating what should not match, which is unbounded.
- **Two callers holding the same scope are indistinguishable.** The `jwt` authenticator validates
  issuer, audience and scope and cannot read a nested claim, so there is no way to say *this*
  pipeline may write and *that* one may not while both hold `keto:write`
  ([ADR 027](../../adr/027-a-machine-caller-is-authorized-by-scope.md)). Separating them means a
  scope per caller, which does not scale, or the authorizer this repository chose not to build.
- **Nothing compares a scope name to what it unlocks.** `keto:write` grants whatever its route
  grants. A rule requiring a scope broader than intended is access nobody notices; the reverse is a
  refusal, which is safe.
- **This module is in the path of every protected request and is not highly available.** One
  replica, one operator, and its failure mode includes admitting somebody rather than only
  refusing them ([§1.4](../../../CONSTITUTION.md#1-boundaries)).
- **The scope vocabulary is not declared anywhere**, in the same way the role catalogue is not
  ([ADR 013](../../adr/013-roles-are-carried-in-the-token.md)). Which scopes exist lives in the
  issuer's console; which are required lives here; nothing checks the two agree.
