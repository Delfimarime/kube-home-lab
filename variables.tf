variable "argocd" {
  type = object({
    namespace       = optional(string, "argocd")
    skip_tls_verify = optional(bool, false)
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

variable "initial_deployment" {
  type        = bool
  description = "First apply of a metrics store: hold back every ServiceMonitor until the operator CRDs exist."
  default     = false
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
    # **Unset here on purpose, and every version pin below follows the same rule.** What each
    # module installs is the module's own fact and is pinned there; a copy at this level would be
    # a second place to change and the one that silently wins, because a value written here is
    # passed down and overrides it. Set one only to make *this cluster* run something other than
    # what the module pins.
    chart_version = optional(string)
    trust_manager = optional(object({
      chart_version = optional(string)
    }), {})

    # Which tenant this unit's own telemetry is stored under. Unset means this cluster's own
    # tenant, which is what certificate management is part of — it is here for the environment
    # that splits its platform across tenants, not because anything needs it stated.
    tenant = optional(string)
  })
  description = "Certificate management: the domain it issues for, the certificates it issues, and the charts it installs."

  validation {
    condition = var.cert_manager.tenant == null || var.observability == null || contains(
      keys(var.observability.tenants), coalesce(var.cert_manager.tenant, "x")
    )
    error_message = "cert_manager.tenant must name one of observability.tenants: a tenant the stores do not have is not rejected by anything downstream — its telemetry is simply collected as unattributed, which reads as data loss and is a typo."
  }
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
    # Unset: the chart the module pins. See `cert_manager.chart_version`.
    chart_version = optional(string)
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

variable "identity" {
  type = object({
    namespace = optional(string, "security")

    # Required: the issuer's address is its whole published contract, so there is no useful
    # configuration of this module that leaves it out.
    hostname = string
    gateway = optional(object({
      name         = optional(string)
      namespace    = optional(string)
      section_name = optional(string)
    }), {})

    database = object({
      host_port     = string
      database_name = optional(string, "keycloak")
      secret_name   = optional(string)
      username_key  = optional(string, "username")
      password_key  = optional(string, "password")
      sslmode       = optional(string, "require")
    })

    bootstrap_admin_secret_name = optional(string)

    # One release pins the operator's manifests and, by leaving `image` unset, the server build
    # that goes with them. Unset here: the release the module pins. See
    # `cert_manager.chart_version`.
    version = optional(string)
    image   = optional(string)

    # Which tenant this unit's own telemetry is stored under. Unlike the other units here it
    # names one by default rather than falling through to the cluster's: an issuer's telemetry is
    # the record of who signed in and from where, which is worth keeping separable from
    # everything else the platform emits.
    tenant = optional(string, "security")
  })
  description = "The environment's OIDC issuer: where it runs, the address it is reached on, and the database it keeps its realm in. null ships no issuer."
  default     = null

  validation {
    condition = var.identity == null || var.observability == null || contains(
      keys(var.observability.tenants), coalesce(var.identity.tenant, "x")
    )
    error_message = "identity.tenant must name one of observability.tenants: a tenant the stores do not have is not rejected by anything downstream — its telemetry is simply collected as unattributed, which reads as data loss and is a typo."
  }
}

variable "git_repository" {
  type = object({
    url      = optional(string, "git@github.com:Delfimarime/kube-home-lab.git")
    revision = optional(string, "main")
  })
  description = "The repository Argo CD reads this repo's own charts from, and the revision it reads them at."
  default     = {}
}

variable "observability" {
  type = object({
    cluster_name = optional(string, "local")
    namespace    = optional(string, "telemetry")
    object_storage = optional(object({
      endpoint       = string
      region         = optional(string, "us-east-1")
      secret_name    = optional(string)
      access_key_key = optional(string, "ACCESS_KEY")
      secret_key_key = optional(string, "SECRET_KEY")
      insecure       = optional(bool, true)
    }))
    components = optional(object({
      metrics = optional(object({
        bucket    = string
        retention = optional(string)
        image_tag = optional(string) # unset: the image the module pins
        object_storage = optional(object({
          endpoint       = string
          region         = optional(string, "us-east-1")
          secret_name    = optional(string)
          access_key_key = optional(string, "ACCESS_KEY")
          secret_key_key = optional(string, "SECRET_KEY")
          insecure       = optional(bool, true)
        }))
      }))
      logs = optional(object({
        bucket        = string
        retention     = optional(string)
        chart_version = optional(string) # unset: the chart the module pins
        object_storage = optional(object({
          endpoint       = string
          region         = optional(string, "us-east-1")
          secret_name    = optional(string)
          access_key_key = optional(string, "ACCESS_KEY")
          secret_key_key = optional(string, "SECRET_KEY")
          insecure       = optional(bool, true)
        }))
      }))
      traces = optional(object({
        bucket        = string
        retention     = optional(string)
        chart_version = optional(string) # unset: the chart the module pins
        object_storage = optional(object({
          endpoint       = string
          region         = optional(string, "us-east-1")
          secret_name    = optional(string)
          access_key_key = optional(string, "ACCESS_KEY")
          secret_key_key = optional(string, "SECRET_KEY")
          insecure       = optional(bool, true)
        }))
      }))
    }), {})
    retention = optional(object({
      unattributed = optional(string, "24h")
      default      = optional(string, "168h")
    }), {})
    tenants = optional(map(object({
      metrics = optional(object({
        limits = optional(object({
          ingestion_rate       = optional(number)
          ingestion_burst_size = optional(number)
          max_series           = optional(number)
          retention            = optional(string)
        }), {})
      }), {})
      logs = optional(object({
        limits = optional(object({
          ingestion_rate_mb       = optional(number)
          ingestion_burst_size_mb = optional(number)
          max_streams             = optional(number)
          retention               = optional(string)
        }), {})
      }), {})
      traces = optional(object({
        limits = optional(object({
          ingestion_rate_bytes = optional(number)
          max_traces           = optional(number)
          retention            = optional(string)
        }), {})
      }), {})
    })), { lab = {} })
    default_tenant = optional(string, "default")
    expose = optional(object({
      hostname = optional(string)
      gateway = optional(object({
        name         = optional(string)
        namespace    = optional(string)
        section_name = optional(string)
      }), {})
    }), {})
    console = optional(object({
      hostname      = optional(string)
      chart_version = optional(string) # unset: the chart the module pins
      tenant        = optional(string)
      gateway = optional(object({
        name         = optional(string)
        namespace    = optional(string)
        section_name = optional(string)
      }), {})
      database = object({
        host_port     = string
        secret_name   = optional(string)
        database_name = optional(string, "grafana")
        username_key  = optional(string, "username")
        password_key  = optional(string, "password")
        sslmode       = optional(string, "require")
      })
      admin = optional(object({
        secret_name  = optional(string)
        user_key     = optional(string, "admin-user")
        password_key = optional(string, "admin-password")
      }), {})
      oidc = optional(object({
        issuer_url   = string
        client_id    = string
        secret_name  = optional(string)
        secret_key   = optional(string, "client-secret")
        scopes       = optional(list(string), ["openid", "profile", "email"])
        groups_claim = optional(string)
      }))
    }))
  })
  description = "Telemetry: which signals are collected and where they land, who may be written as, and the one console over them. null ships neither half."
  default     = null
  validation {
    condition     = var.observability == null || contains(keys(var.observability.tenants), var.observability.default_tenant)
    error_message = "observability.default_tenant must name one of observability.tenants: it is what this cluster's own scraping and log tailing are written as, and deriving it from map ordering is a rule obvious only to whoever wrote it."
  }

  validation {
    condition = var.observability == null || try(var.observability.console.tenant, null) == null || contains(
      keys(var.observability.tenants), try(var.observability.console.tenant, "")
    )
    error_message = "observability.console.tenant must name one of observability.tenants: a tenant the stores do not have collects as unattributed rather than failing, which reads as the console's own telemetry going missing."
  }
}

# The relationship store: one place answering whether a subject may act on a particular resource.
# Null is not shipped.
variable "resource_authorization" {
  type = object({
    namespace            = optional(string, "security")
    database_secret_name = optional(string)
    tenant               = optional(string)

    # The workloads permitted to reach the write port, one entry each. **Applications, not platform
    # modules**: an application that grants access to a resource it owns writes the tuple itself,
    # and this repository does not deploy those workloads — so their selectors are stated by the
    # environment rather than read from a module output.
    write_access_from = map(object({
      namespace = string
      labels    = map(string)
    }))

    # The permission model, said one of two ways and never both.
    #
    # `file` is a path relative to this root, holding a model somebody wrote. `namespaces`
    # describes the same thing as data and the module generates the model from it — bounded to one
    # level of composition and three kinds of term, which is what makes `file` the escape hatch
    # rather than a legacy form. Neither set ships a default model that grants nobody anything.
    #
    # **`namespaces` is deliberately untyped here.** Its shape belongs to the module, is stated
    # there in full, and is checked by that module's validations — which resolve every name a term
    # references and refuse a name that is both a relation and a permit. Restating a thirty-line
    # nested type in this file would be a second copy to disagree with the first.
    model = optional(object({
      file       = optional(string)
      namespaces = optional(any)
    }))
  })
  default     = null
  description = "The relationship store, and how this cluster's permission model is stated."

  validation {
    condition     = try(var.resource_authorization.model, null) == null ? true : !(try(var.resource_authorization.model.file, null) != null && try(var.resource_authorization.model.namespaces, null) != null)
    error_message = "resource_authorization.model.file and .namespaces are two ways to say the same thing: set one, or neither for the default."
  }

  # An empty string is a caller who meant to name a file and did not, and would otherwise resolve
  # to the root directory itself.
  validation {
    condition     = try(var.resource_authorization.model.file, null) == null ? true : length(trimspace(var.resource_authorization.model.file)) > 0
    error_message = "resource_authorization.model.file must be null or name a file. Null ships the default model."
  }
}
