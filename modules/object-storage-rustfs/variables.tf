# Where the object store and its credential live. One namespace, one workload.
variable "namespace" {
  type        = string
  description = "Namespace for the object store and the Secret holding its access key."
  default     = "object-storage"
}

# Only the namespace. Nothing about *reaching* Argo CD is a module input.
variable "argocd" {
  type = object({
    namespace = optional(string, "argocd")
  })
  description = "Where the ApplicationSet is created."
  default     = {}
}

# The Secret holding the access key pair.
#
#   null  this module renders it, empty, with the keys the workload reads, and the Application
#         ignores its contents from then on. An operator fills it in.
#   set   an existing Secret this module only reads. Nothing here creates, owns or prunes it,
#         which is also how an environment keeps the credential outside this module's lifecycle.
#
# Absence of a name is the trigger rather than a flag, so there is no configuration in which this
# module both renders a placeholder and points somewhere else.
variable "secret_name" {
  type        = string
  description = "Existing Secret holding the access key pair. null renders a placeholder instead."
  default     = null
  validation {
    condition     = var.secret_name == null || can(regex("^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$", coalesce(var.secret_name, "x")))
    error_message = "secret_name must be a lower-case DNS subdomain name, e.g. \"object-storage-credentials\"."
  }
}

variable "region" {
  type        = string
  description = "The region every S3 client must be configured with."
  default     = "af-south-1"
}

variable "storage" {
  type = object({
    node_selector = optional(map(string))
    size          = optional(string, "20Gi")
    class         = optional(string, "local-path")
  })
  description = "The volume behind every bucket: how big, which StorageClass, and which node."
  default     = {}
  validation {
    condition     = can(regex("^[0-9]+(Mi|Gi|Ti)$", var.storage.size))
    error_message = "storage.size must be a Kubernetes quantity in Mi, Gi or Ti, e.g. \"20Gi\" — a value the API server rejects fails at sync time rather than here."
  }
}

variable "rustfs" {
  type = object({
    chart_version = optional(string, "0.12.0")
  })
  description = "The RustFS chart."
  default     = {}
}

# This workload serves two things on two ports, and they are exposed independently.
#
#   api                 the S3 API. Every store writes here, over cluster DNS, and needs no route
#                       at all. Routing it makes stored objects readable *and deletable* by
#                       whatever reaches the listener.
#   management_console  the admin UI over every stored object, authenticated by the same access
#                       key every consumer already holds.
#
# Each takes its own hostname and its own Gateway, so the two can sit on different listeners —
# which is the point: the API belongs behind mTLS whether or not the console is reachable at all.
# `hostname` is null by default for both, and null is what "not routed" means.
#
# **`port` is one input driving two chart values that must agree**, which is why it is here rather
# than left to a values override. The Service port, its targetPort and the containerPort all
# follow `service.<x>.port`; what the process actually binds follows `config.rustfs.address` and
# `console_address`. Setting one without the other produces a Service pointing at a port nothing
# is listening on, and a pod that never passes its readiness probe.
variable "services" {
  type = object({
    api = optional(object({
      port     = optional(number, 9000)
      hostname = optional(string)
      gateway = optional(object({
        name         = string
        namespace    = string
        section_name = optional(string)
      }))
    }), {})

    management_console = optional(object({
      port     = optional(number, 9001)
      hostname = optional(string)
      gateway = optional(object({
        name         = string
        namespace    = string
        section_name = optional(string)
      }))
    }), {})
  })
  description = "The two surfaces this workload serves: which port each listens on, and whether and how each is exposed."
  default     = {}

  validation {
    condition     = var.services.api.port != var.services.management_console.port
    error_message = "services.api.port and services.management_console.port must differ: they are two ports on one Service, and one number cannot name both."
  }

  validation {
    condition = alltrue([
      for p in [var.services.api.port, var.services.management_console.port] :
      p > 0 && p < 65536
    ])
    error_message = "each service's port must be between 1 and 65535."
  }

  # `null` is a valid value of every type, so the object's shape alone would let a caller name a
  # hostname while leaving the Gateway unnamed — which renders a route attached to nothing and
  # fails at sync time as a Gateway API error nobody reads.
  validation {
    condition = alltrue([
      for s in [var.services.api, var.services.management_console] :
      s.hostname == null || (
        try(length(s.gateway.name), 0) > 0 && try(length(s.gateway.namespace), 0) > 0
      )
    ])
    error_message = "a service with a hostname needs gateway.name and gateway.namespace: an HTTPRoute cannot be written without a Gateway to attach to."
  }
}

# Only consulted when `secret_name` is null, because that is the only case in which this module
# renders a chart of this repository's rather than an upstream one.
variable "git_repository" {
  type = object({
    url      = optional(string, "git@github.com:Delfimarime/kube-home-lab.git")
    revision = optional(string, "main")
  })
  description = "The repository Argo CD reads this repo's own charts from, and the revision it reads them at."
  default     = {}
}
