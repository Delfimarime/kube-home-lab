# Where the operator, the Keycloak instance and the Secrets it reads live. One namespace, and not
# by preference: upstream's namespaced manifests grant the operator permission over the namespace
# it is installed into and no other, so an instance placed anywhere else is one its own controller
# cannot see.
variable "namespace" {
  type        = string
  description = "Namespace for the operator, the Keycloak instance and the Secrets it reads."
  default     = "security"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a lower-case DNS label, e.g. \"security\"."
  }
}

# Only the namespace. Nothing about *reaching* Argo CD is a module input.
variable "argocd" {
  type = object({
    namespace = optional(string, "argocd")
  })
  description = "Where the ApplicationSet is created."
  default     = {}
}

# The shared database contract, and — as in the console — the one place this module departs from
# "null means not wired": **it is required.** Keycloak keeps its realm, its users and every
# session in PostgreSQL, there is no embedded database worth running, and the server does not
# start without one.
#
# `secret_name` is the same input in two states, and there is no second flag to disagree with it:
#
#   null  this module renders the Secret, empty, with the two keys below, and the Application
#         ignores its contents from then on. An operator types the values in.
#   set   an existing Secret this module only reads. Nothing here creates, owns or prunes it.
#
# **`sslmode` reaches Keycloak inside a JDBC URL**, because the `Keycloak` resource has no field
# for it. This module therefore builds `spec.db.url` and sets host, port and database nowhere
# else — the resource ignores those fields whenever `url` is present, so writing both would be
# one fact in two places with a silent winner.
variable "database" {
  type = object({
    host_port     = string
    database_name = string
    secret_name   = optional(string)
    username_key  = optional(string, "username")
    password_key  = optional(string, "password")
    sslmode       = optional(string, "require")
  })
  description = "The PostgreSQL Keycloak keeps its realm, users and sessions in, and the Secret its credential is read from."
  default     = null

  validation {
    condition     = var.database != null
    error_message = "database is required: Keycloak keeps its realm, its users and every session in PostgreSQL, there is no embedded fallback worth running, and the server does not start without one."
  }

  validation {
    condition     = var.database == null || can(regex("^[^:/ ]+:[0-9]+$", try(var.database.host_port, "")))
    error_message = "database.host_port must be a host and a port, e.g. \"postgresql.storage.svc.cluster.local:5432\" — the two go into a JDBC URL verbatim and an address with no port has no default worth guessing."
  }

  validation {
    condition     = var.database == null || contains(["disable", "require", "verify-ca", "verify-full"], try(var.database.sslmode, ""))
    error_message = "database.sslmode must be one of disable, require, verify-ca or verify-full: it is appended to a JDBC URL verbatim, so anything else reaches the driver as a query parameter and fails at start-up."
  }

  validation {
    condition     = var.database == null || try(var.database.secret_name, null) == null || can(regex("^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$", try(var.database.secret_name, "")))
    error_message = "database.secret_name must be a lower-case DNS subdomain name, e.g. \"keycloak-db-credentials\"."
  }

  validation {
    condition     = var.database == null || try(var.database.username_key, "") != try(var.database.password_key, "")
    error_message = "database.username_key and database.password_key must differ: they are two keys of one Secret, and one name cannot carry both."
  }
}

# **The one module here where a null gateway is not a valid state.** Everywhere else null means
# "not exposed", which is a workload reachable by port-forward and a perfectly good configuration.
# Here `issuer_url` is built from the hostname, so a null gateway is a module that publishes no
# address and that nothing can be wired to.
#
# Keycloak agrees, which is worth knowing: `hostname-strict` defaults to true, so the server
# refuses to infer its own address. The requirement below is the same rule stated a variable
# earlier, where the error message can explain itself.
#
# `section_name` names the **ordinary** TLS listener. The mTLS listener exists for machine callers
# and a browser cannot present a client certificate, so it is never the right answer for a login
# page.
variable "gateway" {
  type = object({
    name         = string
    namespace    = string
    hostname     = string
    section_name = optional(string)
  })
  description = "The Gateway, listener and hostname the issuer is reached on."
  default     = null

  validation {
    condition     = var.gateway != null
    error_message = "gateway is required: issuer_url is built from its hostname, so an unexposed issuer publishes nothing and no consumer can be wired to it — this is the one module where null does not mean \"not exposed\"."
  }

  validation {
    condition     = var.gateway == null || can(regex("^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$", try(var.gateway.hostname, "")))
    error_message = "gateway.hostname must be a DNS name, without a scheme and without a path — it becomes an HTTPRoute hostname, the server's own hostname, and the host half of issuer_url."
  }
}

# The first administrator: the account used to sign in and configure everything this module does
# not. Same two states as every credential here.
#
# **There are no key inputs beside it**, and that is the operator's doing rather than an omission.
# It reads `username` and `password` from this Secret by fixed name, so an input for either would
# be a knob with exactly one correct setting.
#
# It is also the break-glass route when the realm's configuration is wrong, which is why it is not
# deleted after first use — and why it is a static credential that needs an owner.
variable "bootstrap_admin_secret_name" {
  type        = string
  description = "Existing Secret holding the bootstrap administrator. null renders a placeholder instead."
  default     = null

  validation {
    condition     = var.bootstrap_admin_secret_name == null || can(regex("^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$", coalesce(var.bootstrap_admin_secret_name, "x")))
    error_message = "bootstrap_admin_secret_name must be a lower-case DNS subdomain name, e.g. \"keycloak-bootstrap-admin\"."
  }
}

# An object rather than a bare bool so that whatever else scraping needs has somewhere to go
# without renaming the input a second time.
#
# **`enabled` is written into `spec.serviceMonitor.enabled` and never omitted.** That field
# defaults to *true*, so leaving it unset on a cluster without the Prometheus operator's CRDs
# fails the sync — the one default here that points the wrong way.
#
# `tenant` reaches the Service through `spec.serviceMonitor.labels`. **It does not reach the
# pods**: the resource exposes no supported pod-label field, so this workload's logs are collected
# as the cluster's own tenant whatever is set here. Every other module labels both; this one
# labels what it can.
variable "metrics" {
  type = object({
    enabled = optional(bool, false)
    tenant  = optional(string)
  })
  description = "Whether the cluster has the scrape CRDs and a collector reading them, and the tenant this workload's metrics belong to."
  default     = {}
}

# One version pinning two things. It is the git tag upstream's operator manifests are read at, and
# — by omission — the server build too: leaving `image` null lets the operator run the Keycloak it
# was released with, which keeps the pair matched without anyone maintaining it.
#
# Setting `image` takes that guarantee back, and is here for the environment that has to pin a
# rebuild. An upgrade is this one line, and the CRDs come with it.
variable "keycloak" {
  type = object({
    version = optional(string, "26.7.2")
    image   = optional(string)
  })
  description = "The Keycloak release: the tag the operator's manifests are read at, and an optional override for the server image."
  default     = {}

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.keycloak.version))
    error_message = "keycloak.version must be a three-part release, e.g. \"26.7.2\" — it is a git tag on upstream's manifest repository, and a tag that does not exist fails at sync time as a repository error rather than here."
  }
}

# Only consulted for this repository's own charts — the instance chart, and a placeholder Secret
# where one is rendered. Upstream's manifest repository is a constant in this module rather than
# an input, because it has exactly one correct value.
variable "git_repository" {
  type = object({
    url      = optional(string, "git@github.com:Delfimarime/kube-home-lab.git")
    revision = optional(string, "main")
  })
  description = "The repository Argo CD reads this repo's own charts from, and the revision it reads them at."
  default     = {}
}
