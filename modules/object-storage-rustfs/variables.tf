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

variable "secret_template" {
  type = object({
    repo_url = optional(string, "git@github.com:Delfimarime/kube-home-lab.git")
    path     = optional(string, "modules/secret-template/helm/secret-template")
    revision = optional(string, "main")
  })
  description = "Where Argo CD reads the Secret chart from."
  default     = {}
}
