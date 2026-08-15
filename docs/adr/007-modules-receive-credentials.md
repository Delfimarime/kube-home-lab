# 007. Module input contracts: providers publish addresses, consumers receive references

**Status:** accepted · **Scope:** platform · **Date:** 2026-08-05 ·
revised 2026-08-09 (absorbed [ADR 006](006-shared-gateway-input.md))

## Context

An identity provider, a database and a Gateway all have to be wired to the things that use
them. Two questions follow: which side owns the credential, and what shape the wiring takes
at the call site.

An earlier draft had `openid-connect-keycloak` accept a map of clients and output their IDs
and secrets. That makes the identity provider aware of every consumer, and puts every client
secret in one module's state.

On shape, the alternative to a shared contract is each module taking whatever its own chart
happens to expect — which makes every call site an exercise in per-chart archaeology.

## Decision

**A provider module publishes only its own address. A consumer module receives a
fully-formed reference.**

`openid-connect-keycloak` outputs `issuer_url` and `discovery_url`. It accepts no client list
and outputs no client credentials.

**Every consumer module takes the same three optional inputs, in one shape each**, and each
defaults to `null` — meaning "not wired", never "disabled by a flag".

```hcl
variable "gateway" {
  type = object({
    name         = string
    namespace    = string
    hostname     = string
    section_name = optional(string)
  })
  default = null
}

variable "database" {
  type = object({
    host_port     = string
    database_name = string
    secret_name   = string
    username_key  = optional(string, "username")
    password_key  = optional(string, "password")
    sslmode       = optional(string, "require")
  })
  default = null
}

variable "oidc" {
  type = object({
    issuer_url   = string
    client_id    = string
    secret_name  = string
    secret_key   = optional(string, "client-secret")
    scopes       = optional(list(string), ["openid", "profile", "email"])
    groups_claim = optional(string)
  })
  default = null
}
```

`database` and `oidc` carry a Secret *reference*, never a password.

How a module turns `gateway` into an actual `HTTPRoute` is a separate decision — see
[ADR 010](010-resources-delivered-via-chart.md).

## Rationale

- The identity provider does not need to know its consumers, and a new consumer is not a
  change to the identity provider.
- Credential values never enter a values.yaml, and therefore never enter the rendered Helm
  values inside an Argo CD `Application` spec — which would otherwise sit in etcd in
  plaintext.
- The alternative, each consumer registering its own client, requires Keycloak admin
  credentials in every module's state. Worse.
- One input shape means no per-chart archaeology at the call site: every module reads
  `var.gateway` the same way, regardless of what its own chart expects internally.
- The same principle scales past this repo's boundary. A module receiving `database` knows a
  host, a port and a Secret — not where PostgreSQL runs, whether it is shared between
  environments, or who created it. That ignorance is the feature.

## Consequences

- **Client registration happens outside OpenTofu.** For a handful of consumers that change
  approximately never, registering them by hand in Keycloak's console is less machinery than
  a provider plus a machine user plus a PAT bootstrap. Revisit at ~fifteen clients with a
  dedicated registration unit; the consumer contract above would not change.
- This removes a constraint that previously looked forced: because OpenTofu never calls
  Keycloak's admin API, there is no two-phase install-then-configure split.
  `openid-connect-keycloak` is one unit.
- **Hostnames must be defined once per environment**, in that environment's `env.hcl`, and
  fed to both the identity provider and its consumers. Deriving a redirect URI from a
  consumer's output while the consumer takes `client_id` from the provider is a dependency
  cycle Terragrunt will refuse. See [ADR 011](011-environments-are-clusters.md).
- Backends stay unexposed by simply not being passed a gateway. In the observability module,
  `var.gateway` means Grafana's route, because Grafana is the only exposed surface.
- **Something must materialise the referenced Secrets, and nothing in this repo does.** When and
  by whom is an operational matter, not a module's concern — but it is currently nobody's. See
  [the open questions](../requirements.md#open-questions).
- State holds no credential, which is what makes keeping it beside the workloads defensible —
  see [ADR 012](012-state-is-per-environment.md).
