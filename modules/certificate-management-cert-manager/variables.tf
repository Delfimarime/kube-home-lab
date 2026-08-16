# Where this module puts everything: the controllers, the two authorities, and the Secrets
# holding their private keys. One namespace rather than two, because cert-manager resolves a
# ClusterIssuer's CA Secret in its own namespace by default — splitting them means remembering to
# point --cluster-resource-namespace back, and forgetting produces a ClusterIssuer that never
# becomes ready and says only "secret not found".
variable "namespace" {
  type        = string
  description = "Namespace for cert-manager, trust-manager and the authorities."
  default     = "cert-manager"
}

# Only the namespace. Nothing about *reaching* Argo CD is a module input: ARGOCD_SERVER,
# ARGOCD_AUTH_TOKEN and ARGOCD_INSECURE come from the operator's environment, and `plain_text` is
# the root module's.
variable "argocd" {
  type = object({
    namespace = optional(string, "argocd")
  })
  description = "Where the ApplicationSet is created."
  default     = {}
}

# The internal DNS suffix every name this module issues is built from. It is required: a
# certificate authority with no domain has nothing to be an authority over.
variable "domain" {
  type        = string
  description = "Internal DNS suffix, e.g. lab.internal. The wildcard certificate is *.<domain>."

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$", var.domain))
    error_message = "domain must be a dotted DNS name in lower case, e.g. lab.internal — not a URL and not a wildcard."
  }
}

# Both authorities, which are fixed at two: `server` signs what serves TLS, `client` signs what
# authenticates to a listener. A single root would let the wildcard server certificate
# authenticate as a client, since a listener trusts a CA and not a purpose — whether that is
# caught would depend on the Gateway enforcing Extended Key Usage, which is implementation
# specific. Two authorities make the separation structural instead.
variable "authority" {
  type = object({
    duration = optional(string, "87600h") # 10y — an authority outlives what it signs
  })
  description = "Knobs shared by both certificate authorities."
  default     = {}
}

# Certificates *in addition to* `default`, which is always issued: the wildcard `*.<domain>` and
# the shared client identity that goes with it.
#
#   mode = "tls"   one certificate, from the server authority
#   mode = "mtls"  a pair — a server certificate *and* a client certificate for the same entry
#
# mTLS is a pair, not a usage. Adding `client auth` to a server certificate would be the simpler
# rendering and it would defeat the two-authority split above: the point is that the server
# certificate is *refused* when presented as a client certificate.
#
# This module issues certificates and never configures a listener. Whether a listener demands the
# client half is the Gateway's, per environment.
variable "certificates" {
  type = map(object({
    mode         = optional(string, "tls")
    dns_names    = optional(list(string), []) # defaults to ["<name>.<domain>"]
    duration     = optional(string, "8760h")  # 1y
    renew_before = optional(string)
  }))
  description = "Certificates beyond the wildcard `default`, keyed by name."
  default     = {}

  validation {
    condition = alltrue([
      for name, c in var.certificates : contains(["tls", "mtls"], c.mode)
    ])
    error_message = "certificates.<name>.mode must be \"tls\" (a server certificate) or \"mtls\" (a server certificate and a client certificate)."
  }

  # `default` is issued by the module from var.domain, so an entry of that name would either be
  # ignored or silently replace the wildcard. Refusing is the only reading that cannot surprise.
  validation {
    condition     = !contains(keys(var.certificates), "default")
    error_message = "\"default\" is reserved: it is the wildcard *.<domain> certificate and its client half, issued from var.domain. Name this entry something else."
  }

  validation {
    condition = alltrue([
      for name, c in var.certificates : can(regex("^[0-9]+h$", c.duration))
    ])
    error_message = "certificates.<name>.duration must be a whole number of hours, e.g. \"8760h\"."
  }
}

# The wildcard, and the shared client identity that pairs with it. Split out from
# `certificates` because it is not optional and its dns_names are derived, not chosen.
# `renew_before` is null by default here, exactly as it is for an additional entry: unset means
# the server half takes cert-manager's own renewal point and the client half takes 720h. Setting
# it applies to both halves. Defaulting it to "720h" would have made `default` behave differently
# from every other entry for no reason a reader could see.
variable "default_certificate" {
  type = object({
    duration     = optional(string, "8760h")
    renew_before = optional(string)
  })
  description = "The always-issued *.<domain> certificate and its client half."
  default     = {}

  # An authority that expires before what it signed is a fleet of certificates that cannot be
  # renewed and a root that has to be redistributed to every device. Compared as whole hours,
  # which is why the format is constrained: cert-manager accepts "8760h0m0s" too, and parsing
  # that here would be a date library nobody asked for. Cross-variable, which pins OpenTofu 1.9.
  validation {
    condition = alltrue(concat(
      [
        can(regex("^[0-9]+h$", var.authority.duration)),
        can(regex("^[0-9]+h$", var.default_certificate.duration)),
        tonumber(trimsuffix(var.authority.duration, "h")) > tonumber(trimsuffix(var.default_certificate.duration, "h")),
      ],
      [
        for name, c in var.certificates :
        tonumber(trimsuffix(var.authority.duration, "h")) > tonumber(trimsuffix(c.duration, "h"))
      ],
    ))
    error_message = "An authority must outlive every certificate it signs: authority.duration must be a whole number of hours strictly greater than default_certificate.duration and every certificates.<name>.duration."
  }
}

variable "trust_bundle" {
  type = object({
    name        = optional(string, "cert-ca-bundle")
    authorities = optional(list(string), ["server"])
  })
  description = "The ConfigMap every namespace receives, and which authorities it carries."
  default     = {}

  # The server authority only, by default. Nothing in-cluster verifies a client certificate —
  # that is the Gateway's job, and it reads the client CA's Secret directly through the
  # ReferenceGrant. Distributing it everywhere would ship material with no reader.
  validation {
    condition = alltrue([
      for name in var.trust_bundle.authorities : contains(["server", "client"], name)
    ])
    error_message = "trust_bundle.authorities may only name \"server\" or \"client\"; there are exactly two authorities."
  }
}

# Not the shared `gateway` object, and deliberately not shaped like it. That shape carries a
# name, a hostname and a section — everything a module needs to *emit a route*. This module emits
# no route; what it needs is the namespace whose Gateway may read these Secrets, and taking the
# whole shape to read one field would force a caller to invent values nothing reads.
#
# null means no ReferenceGrant, which means a Gateway in another namespace cannot reference them.
variable "gateway_namespace" {
  type        = string
  description = "Namespace holding the Gateway whose listeners reference these Secrets."
  default     = null
}

# An object rather than a bare bool so that whatever else scraping needs — an interval, a label —
# has somewhere to go without renaming the input a second time.
variable "metrics" {
  type = object({
    enabled = optional(bool, false)
  })
  description = "Whether this environment has the Prometheus-operator CRDs and a collector reading them."
  default     = {}
}

# Pinned exactly, so an upgrade is a deliberate edit and a chart's values schema cannot change
# underneath this module silently. On cert-manager it is a two-line edit: `crds.enabled` defaults
# to false and was renamed from `installCRDs` at v1.15, with the old name still accepted and
# silently ignored.
variable "cert_manager" {
  type = object({
    chart_version = optional(string, "v1.21.1")
  })
  description = "The cert-manager chart."
  default     = {}
}

variable "trust_manager" {
  type = object({
    chart_version = optional(string, "v0.24.0")
  })
  description = "The trust-manager chart."
  default     = {}
}

# cert-pki is read from git rather than a chart repository, so Argo CD must have this repository
# registered as a source.
variable "git_repository" {
  type = object({
    url      = optional(string, "git@github.com:Delfimarime/kube-home-lab.git")
    revision = optional(string, "main")
  })
  description = "The repository Argo CD reads the authorities chart from, and the revision it reads it at."
  default     = {}
}
