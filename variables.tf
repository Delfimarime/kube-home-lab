variable "argocd" {
  type = object({
    namespace = optional(string, "argocd")
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
      name        = optional(string, "cert-ca-bundle")
      authorities = optional(list(string), ["server"])
    }), {})
    chart_version = optional(string, "v1.21.1")
    trust_manager = optional(object({
      chart_version = optional(string, "v0.24.0")
    }), {})
  })
  description = "Certificate management: the domain it issues for, the certificates it issues, and the charts it installs."
}

variable "object_storage" {
  type = object({
    namespace   = optional(string, "object-storage")
    secret_name = optional(string)
    region      = optional(string, "us-east-1")
    storage = optional(object({
      size          = optional(string, "20Gi")
      class         = optional(string, "local-path")
      node_selector = optional(map(string))
    }), {})
    chart_version = optional(string, "0.12.0")
    services = optional(object({
      api = optional(object({
        port     = optional(number, 9000)
        hostname = optional(string)
        gateway = optional(object({
          name         = optional(string)
          namespace    = optional(string)
          section_name = optional(string)
        }), {})
      }), {})
      management_console = optional(object({
        port     = optional(number, 9001)
        hostname = optional(string)
        gateway = optional(object({
          name         = optional(string)
          namespace    = optional(string)
          section_name = optional(string)
        }), {})
      }), {})
    }), {})
  })
  description = "The S3 endpoint every store writes into: how big its volume is, where its access key comes from, and whether anything outside the cluster can reach it."
  default     = {}
}

variable "git_repository" {
  type = object({
    url      = optional(string, "git@github.com:Delfimarime/kube-home-lab.git")
    revision = optional(string, "main")
  })
  description = "The repository Argo CD reads this repo's own charts from, and the revision it reads them at."
  default     = {}
}
