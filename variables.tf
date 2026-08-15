variable "argocd" {
  type = object({
    namespace  = optional(string, "argocd")
    plain_text = optional(bool, true)
  })
  description = "Where ApplicationSets are created, and how the provider reaches Argo CD."
  default     = {}
}

variable "gateway" {
  type = object({
    namespace    = string
    name         = optional(string)
    hostname     = optional(string)
    section_name = optional(string)
  })
  description = "The cluster's Gateway. Its namespace is what certificate Secrets are granted to."
}

variable "metrics" {
  type = object({
    enabled = optional(bool, false)
  })
  description = "Whether this cluster has the Prometheus-operator CRDs and a collector."
  default     = {}
}

variable "cert_manager" {
  type = object({
    domain    = string
    namespace = optional(string, "cert-manager")

    certificates = optional(map(object({
      mode         = optional(string, "tls")
      dns_names    = optional(list(string), []) # defaults to ["<name>.<domain>"]
      duration     = optional(string, "8760h")
      renew_before = optional(string)
    })), {})

    default_certificate = optional(object({
      duration     = optional(string, "8760h")
      renew_before = optional(string)
    }), {})

    authority = optional(object({
      duration = optional(string, "87600h")
    }), {})

    trust_bundle = optional(object({
      name        = optional(string, "lab-ca-bundle")
      authorities = optional(list(string), ["server"])
    }), {})

    chart_version = optional(string, "v1.21.1")

    trust_manager = optional(object({
      chart_version = optional(string, "v0.24.0")
    }), {})

    lab_pki = optional(object({
      repo_url = optional(string, "git@github.com:Delfimarime/kube-home-lab.git")
      path     = optional(string, "modules/certificate-management-cert-manager/helm/lab-pki")
      revision = optional(string, "main")
    }), {})
  })
  description = "Certificate management: the domain it issues for, the certificates it issues, and the charts it installs."
}
