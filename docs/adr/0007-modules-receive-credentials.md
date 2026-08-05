# 7. Providers publish addresses; consumers receive credentials

**Status:** accepted · **Date:** 2026-08-05

## Context

An identity provider and a database both need to be wired to the things that use them. The
question is which side owns the credential.

An earlier draft had `openid-connect-zitadel` accept a map of clients and output their
IDs and secrets. That makes the identity provider aware of every consumer, and puts every
client secret in one module's state.

## Decision

**A provider module publishes only its own address. A consumer module receives a
fully-formed credential object.**

`openid-connect-zitadel` outputs `issuer_url` and `discovery_url`. It accepts no client
list and outputs no client credentials.

Consumers declare what they need, in one shape each:

```hcl
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

Both carry a Secret *reference*, never a password. Both default to `null`, meaning
"not wired".

## Rationale

- The identity provider does not need to know its consumers, and a new consumer is not a
  change to the identity provider.
- Credential values never enter a values.yaml, and therefore never enter the rendered Helm
  values inside an Argo CD `Application` spec — which would otherwise sit in etcd in
  plaintext.
- The alternative, each consumer registering its own client, requires Zitadel admin
  credentials in every module's state. Worse.

## Consequences

- **Client registration happens outside Terraform.** For a handful of consumers that change
  approximately never, registering them by hand in Zitadel's console is less machinery than
  a provider plus a machine user plus a PAT bootstrap. Revisit at ~fifteen clients with a
  dedicated registration unit; the consumer contract above would not change.
- This removes a constraint that previously looked forced: because Terraform never calls
  Zitadel's management API, there is no two-phase install-then-configure split.
  `openid-connect-zitadel` is one unit.
- **Hostnames must be defined once**, as `root.hcl` locals, and fed to both the identity
  provider and its consumers. Deriving a redirect URI from a consumer's output while the
  consumer takes `client_id` from the provider is a dependency cycle Terragrunt will refuse.
- Something must materialise the referenced Secrets — see [ADR 9](0009-secret-delivery-openbao-eso.md).
