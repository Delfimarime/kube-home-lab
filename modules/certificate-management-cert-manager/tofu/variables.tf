# Where this module puts everything: the controllers, the authorities, and the Secrets holding
# their private keys. One namespace rather than two, because cert-manager resolves a
# ClusterIssuer's CA Secret in its own namespace by default — splitting them means remembering to
# point --cluster-resource-namespace back, and forgetting produces a ClusterIssuer that never
# becomes ready and says only "secret not found".
variable "namespace" {
  type        = string
  description = "Namespace for cert-manager, trust-manager and the authorities."
  default     = "certificates"
}

# Only the namespace. Nothing about *reaching* Argo CD is a module input: ARGOCD_SERVER,
# ARGOCD_AUTH_TOKEN and ARGOCD_INSECURE come from the operator's environment so no credential
# reaches a tfvars file or state, and `plain_text` — the one field with no environment variable —
# is read from `env.hcl` by the provider block `root.hcl` generates. This module never sees it.
#
# Where the ApplicationSet object is created is a different question, and that one is ours.
variable "argocd" {
  type = object({
    namespace = optional(string, "argocd")
  })
  description = "Where the ApplicationSet is created."
  default     = {}
}

# The module. Each entry is one authority and the single certificate it signs; the 1:1 rule
# lives in this type rather than in review, so a second certificate needs a second authority —
# which is a claim that the two are genuinely different (LOCAL-002).
variable "certificate_authorities" {
  type = map(object({
    common_name = string
    duration    = optional(string, "87600h") # 10y — an authority outlives what it signs
    certificate = object({
      common_name  = optional(string)
      dns_names    = optional(list(string), [])
      usages       = list(string)
      duration     = optional(string, "8760h") # 1y
      renew_before = optional(string)
    })
  }))
  description = "Self-signed authorities, keyed by role. Each signs exactly one certificate."

  default = {
    server = {
      common_name = "lab server CA"
      certificate = {
        dns_names = ["*.lab.internal"]
        usages    = ["server auth"]
      }
    }
    client = {
      common_name = "lab client CA"
      certificate = {
        common_name = "lab client"
        usages      = ["client auth"]
        # Short on purpose: cert-manager renews at two thirds of lifetime by default, which
        # would leave the expiry metric describing a certificate nobody has deployed.
        renew_before = "720h"
      }
    }
  }

  validation {
    condition     = length(var.certificate_authorities) > 0
    error_message = "certificate_authorities must name at least one authority; a module that issues nothing has no reason to be applied."
  }

  # CERT-06. Durations are compared as whole hours, which is why the format is constrained:
  # cert-manager accepts "8760h0m0s" too, and parsing that here would be a date library nobody
  # asked for. An authority that expires before what it signed is a fleet of certificates that
  # cannot be renewed and a root that has to be redistributed to every device.
  validation {
    condition = alltrue([
      for name, a in var.certificate_authorities :
      can(regex("^[0-9]+h$", a.duration)) &&
      can(regex("^[0-9]+h$", a.certificate.duration)) &&
      tonumber(trimsuffix(a.duration, "h")) > tonumber(trimsuffix(a.certificate.duration, "h"))
    ])
    error_message = "An authority must outlive the certificate it signs: every certificate_authorities.<name>.duration must be a whole number of hours ('87600h') strictly greater than its certificate.duration."
  }

  validation {
    condition = alltrue([
      for name, a in var.certificate_authorities :
      length(a.certificate.dns_names) > 0 || a.certificate.common_name != null
    ])
    error_message = "Each certificate needs either dns_names or a common_name: a server certificate names hosts, a client certificate names itself, and one with neither identifies nothing."
  }
}

variable "trust_bundle" {
  type = object({
    name        = optional(string, "lab-ca-bundle")
    authorities = list(string)
  })
  description = "The ConfigMap every namespace receives, and which authorities it carries."

  default = {
    # The server authority only. Nothing in-cluster verifies a client certificate — that is the
    # Gateway's job, and it reads the client CA's Secret directly through the ReferenceGrant.
    # Distributing it everywhere would ship material with no reader (ADR 018).
    authorities = ["server"]
  }

  # Cross-variable validation, which is what pins the required OpenTofu version at 1.9. The
  # chart fails on this too; catching it at plan time turns a failed sync into a failed plan.
  validation {
    condition = alltrue([
      for name in var.trust_bundle.authorities :
      contains(keys(var.certificate_authorities), name)
    ])
    error_message = "trust_bundle.authorities may only name keys of certificate_authorities; distributing an authority that does not exist produces a Bundle that never becomes ready."
  }
}

# Not the `gateway` contract, and deliberately not shaped like it. That contract carries a name,
# a hostname and a section — everything a module needs to *emit a route*. This module emits no
# route; what it needs is the namespace whose Gateway may read these Secrets, and taking the
# whole shape would force a caller to invent a hostname nothing here reads.
#
# A module declares what it needs (ADR 007, rule 3). null means no ReferenceGrant, which means a
# Gateway in another namespace cannot reference the certificates.
variable "gateway_namespace" {
  type        = string
  description = "Namespace holding the Gateway whose listeners reference these Secrets. null means no ReferenceGrant."
  default     = null
}

# ADR 016. An object rather than a bare bool so that what else scraping needs — an interval, a
# label — has somewhere to go without renaming the input a second time.
variable "metrics" {
  type = object({
    enabled = optional(bool, false)
  })
  description = "Whether this environment has the Prometheus-operator CRDs and a collector reading them."
  default     = {}
}

# Pinned exactly. An upgrade is a deliberate edit (ADR 010), and on cert-manager it is a
# two-line edit: `crds.enabled` defaults to false and was renamed from `installCRDs` at v1.15,
# with the old name still accepted and silently ignored.
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

# lab-pki is read from git rather than a chart repository, so Argo CD must have this repository
# registered as a source. Public repo, so no credential is registered for it.
variable "lab_pki" {
  type = object({
    repo_url = optional(string, "https://github.com/Delfimarime/kube-home-lab.git")
    path     = optional(string, "modules/certificate-management-cert-manager/helm/lab-pki")
    revision = optional(string, "main")
  })
  description = "Where Argo CD reads the authorities chart from."
  default     = {}
}
