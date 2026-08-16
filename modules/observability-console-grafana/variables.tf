# Where the console and the credential it reads live. One namespace, one workload.
variable "namespace" {
  type        = string
  description = "Namespace for Grafana and the Secret holding its database credential."
  default     = "observability"

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a lower-case DNS label, e.g. \"observability\"."
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

# The three stores, as addresses rather than as switches.
#
# **A datasource's type is not an input.** An address named `metrics_url` becomes a `prometheus`
# datasource, `logs_url` a `loki` one and `traces_url` a `tempo` one. Replacing the store behind a
# capability means replacing it with something speaking the same query API, so a type input would
# be flexibility nobody would ever spend.
#
# They are addresses rather than booleans because a flag and the store it claims to describe are
# two truths that could disagree, and every correlation link would then be wired against a
# datasource that is not there. An address is either reachable or `null`, and cannot lie about it.
#
# The check that at least one of the three is set lives here rather than in three places: one
# console over nothing is a console with no datasource, no correlation and nothing to show, and
# whichever of the three names the mistake, the mistake is the same one.
variable "metrics_url" {
  type        = string
  description = "Base URL of the metrics store's query API. null when the environment stores no metrics."
  default     = null

  validation {
    condition     = var.metrics_url == null || can(regex("^https?://", coalesce(var.metrics_url, "x")))
    error_message = "metrics_url must be an http:// or https:// URL — a bare host and port produces a datasource Grafana cannot query."
  }

  validation {
    condition     = anytrue([var.metrics_url != null, var.logs_url != null, var.traces_url != null])
    error_message = "at least one of metrics_url, logs_url and traces_url must be set: with all three null there is no datasource to create and nothing for the console to read."
  }
}

variable "logs_url" {
  type        = string
  description = "Base URL of the log store's query API. null when the environment stores no logs."
  default     = null

  validation {
    condition     = var.logs_url == null || can(regex("^https?://", coalesce(var.logs_url, "x")))
    error_message = "logs_url must be an http:// or https:// URL — a bare host and port produces a datasource Grafana cannot query."
  }
}

variable "traces_url" {
  type        = string
  description = "Base URL of the trace store's query API. null when the environment stores no traces."
  default     = null

  validation {
    condition     = var.traces_url == null || can(regex("^https?://", coalesce(var.traces_url, "x")))
    error_message = "traces_url must be an http:// or https:// URL — a bare host and port produces a datasource Grafana cannot query."
  }
}

# The shared database contract, and the one place this module departs from "null means not wired":
# **it is required.** Grafana's users, preferences, annotations and every alert rule live in
# PostgreSQL and are the only thing here that cannot be regenerated from git; there is no SQLite
# fallback and Grafana does not start without one. Making it required also means Grafana owns no
# volume at all.
#
# `secret_name` is the same input in two states, and there is no second flag that could disagree
# with it:
#
#   null  this module renders the Secret, empty, with the two keys below, and the Application
#         ignores its contents from then on. An operator types the values in.
#   set   an existing Secret this module only reads. Nothing here creates, owns or prunes it.
#
# The default is `null` so that omitting the input entirely produces the message below rather than
# OpenTofu's generic one — the input is mandatory, and the reason it is mandatory is worth stating
# where somebody meets it.
variable "database" {
  type = object({
    host_port     = string
    database_name = string
    secret_name   = optional(string)
    username_key  = optional(string, "username")
    password_key  = optional(string, "password")
    sslmode       = optional(string, "require")
  })
  description = "The PostgreSQL Grafana keeps its own state in, and the Secret its credential is read from."
  default     = null

  validation {
    condition     = var.database != null
    error_message = "database is required: Grafana keeps its users, preferences, annotations and alert rules in PostgreSQL, there is no SQLite fallback, and the workload does not start without one."
  }

  validation {
    condition     = var.database == null || can(regex("^[^:/ ]+:[0-9]+$", try(var.database.host_port, "")))
    error_message = "database.host_port must be a host and a port, e.g. \"postgres.example:5432\" — Grafana takes the two together and rejects an address with no port."
  }

  validation {
    condition     = var.database == null || contains(["disable", "require", "verify-ca", "verify-full"], try(var.database.sslmode, ""))
    error_message = "database.sslmode must be one of disable, require, verify-ca or verify-full: anything else reaches Grafana verbatim and fails at start-up as a driver error."
  }

  validation {
    condition     = var.database == null || try(var.database.secret_name, null) == null || can(regex("^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$", try(var.database.secret_name, "")))
    error_message = "database.secret_name must be a lower-case DNS subdomain name, e.g. \"grafana-db-credentials\"."
  }

  validation {
    condition     = var.database == null || try(var.database.username_key, "") != try(var.database.password_key, "")
    error_message = "database.username_key and database.password_key must differ: they are two keys of one Secret, and one name cannot carry both."
  }
}

# The one routable surface this module has. Grafana is the only thing exposed here — the stores it
# reads are never routed by the module that owns them.
#
# null means not exposed, which is a console reachable only by port-forward. It is a valid state
# and not a broken one.
variable "gateway" {
  type = object({
    name         = string
    namespace    = string
    hostname     = string
    section_name = optional(string)
  })
  description = "The Gateway and hostname Grafana is exposed on. null is not exposed."
  default     = null

  validation {
    condition     = var.gateway == null || can(regex("^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$", try(var.gateway.hostname, "")))
    error_message = "gateway.hostname must be a DNS name, without a scheme and without a path — it becomes an HTTPRoute hostname and Grafana's own root_url."
  }
}

# Grafana's own administrator, which is the break-glass route into a console whose issuer is down —
# the local login form is closed once `oidc` is wired, but this account still authenticates to the
# HTTP API with basic auth.
#
# **The chart must never invent this password.** Left to itself it generates one per render and
# reuses an existing one only by reading the Secret back from the cluster, which manifests
# generated outside a cluster cannot do — so the account's password would change on every
# reconcile and be a value nobody has ever seen. Naming a Secret here is what stops it: the chart
# reads the account from that Secret and creates none.
#
# Same two modes as every other credential, and the same single input expressing them:
#
#   null  this module renders the Secret, empty, with the two keys below. An operator types the
#         values in, and until they do the account has no usable password.
#   set   an existing Secret this module only reads.
variable "admin" {
  type = object({
    secret_name  = optional(string)
    user_key     = optional(string, "admin-user")
    password_key = optional(string, "admin-password")
  })
  description = "The Secret holding Grafana's administrator account — the break-glass credential when the issuer is unreachable."
  default     = {}

  validation {
    condition     = var.admin.secret_name == null || can(regex("^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$", coalesce(var.admin.secret_name, "")))
    error_message = "admin.secret_name must be a lower-case DNS subdomain name, e.g. \"grafana-admin-credentials\"."
  }

  validation {
    condition     = var.admin.user_key != var.admin.password_key
    error_message = "admin.user_key and admin.password_key must differ: they are two keys of one Secret, and one name cannot carry both."
  }
}

# The issuer Grafana delegates authentication and authorization to.
#
# Set, the local login form closes and everything about who may do what comes from the token. Null,
# the form is the only way in. There is no input for the form itself: three of its four states
# would be the derived one restated and the fourth admits nobody.
#
# `secret_name` carries the client secret and takes the same two states as every other credential
# here: named, this module only reads it; null, it renders the placeholder and an operator fills in
# what the issuer's console showed once.
variable "oidc" {
  type = object({
    issuer_url   = string
    client_id    = string
    secret_name  = optional(string)
    secret_key   = optional(string, "client-secret")
    scopes       = optional(list(string), ["openid", "profile", "email"])
    groups_claim = optional(string)
  })
  description = "The OIDC issuer Grafana delegates sign-in and role assignment to. null leaves the local login form on."
  default     = null

  validation {
    condition     = var.oidc == null || can(regex("^https://", try(var.oidc.issuer_url, "")))
    error_message = "oidc.issuer_url must be an https:// URL: Grafana's token exchange and userinfo calls are server-to-server and are not made in the clear."
  }

  validation {
    condition     = var.oidc == null || try(var.oidc.secret_name, null) == null || can(regex("^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$", try(var.oidc.secret_name, "")))
    error_message = "oidc.secret_name must be a lower-case DNS subdomain name, e.g. \"grafana-oidc-credentials\"."
  }

  validation {
    condition     = var.oidc == null || length(try(var.oidc.scopes, [])) > 0
    error_message = "oidc.scopes must name at least one scope; \"openid\" is what makes the exchange an OpenID Connect one at all."
  }
}

# Which tenants are worth looking at, and which of them the console defaults to.
#
# **This is a read-side choice and it cannot disagree with reality.** Nothing validates a tenant
# name on write either, so there is no set of real tenants for this list to be wrong about. A
# tenant nobody writes to shows an empty datasource; a tenant being written to and absent from this
# list is invisible in the console. Both are silent, which is why the list should hold the smallest
# number that is actually useful — every entry multiplies the datasources and every correlation
# link is wired within one tenant and cannot cross into another.
variable "tenants" {
  type        = list(string)
  description = "The tenants to create datasources for. One datasource per tenant per switched-on store."
  default     = ["lab"]

  validation {
    condition     = length(var.tenants) > 0
    error_message = "tenants must name at least one tenant: every read carries X-Scope-OrgID, so a console with no tenant has no datasource it could build."
  }

  validation {
    condition     = length(var.tenants) == length(distinct(var.tenants))
    error_message = "tenants must not repeat — a duplicate renders two datasources with one identifier, and only one of them survives."
  }

  validation {
    condition     = alltrue([for t in var.tenants : can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", t))])
    error_message = "each tenant must be lower-case alphanumerics and dashes: the name is both an X-Scope-OrgID header value and half of a datasource identifier."
  }
}

variable "default_tenant" {
  type        = string
  description = "Which tenant's datasources Grafana marks as its defaults."
  default     = "lab"

  validation {
    condition     = contains(var.tenants, var.default_tenant)
    error_message = "default_tenant must be one of tenants: Grafana needs exactly one default datasource per type, and picking it from list order is a rule that is obvious to whoever wrote it and to nobody else."
  }
}

# The ConfigMap carrying the lab's certificate authority, distributed into every namespace by the
# certificate module and mounted — never created — here.
#
# **It is what makes OIDC work at all.** Every server-to-server call Grafana makes to the issuer is
# against a certificate signed by an authority no container trusts by default; without the mount
# the callback fails with `x509: certificate signed by unknown authority`, which reads as a broken
# OIDC configuration and is not one. Nothing verifies the ConfigMap exists: absent, the pod does
# not start, which is the loud failure; stale, the pod starts and OIDC fails, which is the quiet
# one.
variable "trust_bundle_name" {
  type        = string
  description = "ConfigMap holding the cluster's trust bundle. Mounted whenever oidc is set."
  default     = "cert-ca-bundle"

  validation {
    condition     = var.oidc == null || can(regex("^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$", coalesce(var.trust_bundle_name, "")))
    error_message = "trust_bundle_name must name the trust bundle ConfigMap whenever oidc is set: Grafana reaches the issuer over TLS on every call and trusts nothing signed by the lab authority without it."
  }
}

# An object rather than a bare bool so that whatever else scraping needs — an interval, a label —
# has somewhere to go without renaming the input a second time.
#
# It asserts a fact about the cluster rather than switching a feature on: that the operator's CRDs
# exist and something is reading them. Declared where they do not, the ServiceMonitor fails the
# sync or is never read, and this console would be the one workload whose own health nobody sees.
# `tenant` is which tenant this console's own telemetry is stored under, written onto its Service
# and its pods as a label the collector discovers. Null leaves both unlabelled, which is collected
# as the cluster's own — the ordinary answer for a console that is part of the platform rather than
# of anything running on it.
variable "metrics" {
  type = object({
    enabled = optional(bool, false)
    tenant  = optional(string)
  })
  description = "Whether the cluster has the scrape CRDs and a collector reading them, so this workload declares scraping, and the tenant its own telemetry belongs to."
  default     = {}
}

# The Grafana chart: which version, and an escape hatch for whatever this module does not model.
#
# **A key given in `values` replaces this module's whole value for that key**, with one exception:
# `grafana.ini` is merged section by section, because it carries the database wiring, the login
# form's state and the entire OIDC configuration, and an override that only wanted to add `smtp`
# would otherwise silently take all three away. A section this module wrote is still replaced
# whole. It is here for the setting nobody anticipated, not as a supported second layer.
variable "grafana" {
  type = object({
    chart_version = optional(string, "10.5.15")
    values        = optional(any, {})
  })
  description = "The Grafana chart version, and values merged over the ones this module computes."
  default     = {}
}

# Only consulted when a credential is left unnamed, because a placeholder is the only case in which
# this module renders a chart of this repository's rather than an upstream one.
variable "git_repository" {
  type = object({
    url      = optional(string, "git@github.com:Delfimarime/kube-home-lab.git")
    revision = optional(string, "main")
  })
  description = "The repository Argo CD reads this repo's own charts from, and the revision it reads them at."
  default     = {}
}
