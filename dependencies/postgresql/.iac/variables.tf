variable "argocd_namespace" {
  type        = string
  description = "Namespace the ApplicationSet is created in."
  default     = "argocd"
}

variable "namespace" {
  type        = string
  description = "Existing namespace the PostgreSQL cluster runs in."
  default     = "storage"
}

variable "operator_namespace" {
  type        = string
  description = "Namespace the CloudNativePG operator runs in."
  default     = "cnpg-system"
}

# Also names the generated credentials Secret (`<cluster_name>-app`) and the Services
# (`<cluster_name>-rw` / `-ro` / `-r`). The Secret name cannot be set independently: naming one
# in initdb makes CloudNativePG expect it to already exist, and nothing here creates Secrets.
variable "cluster_name" {
  type    = string
  default = "postgresql"
}

variable "argocd_plain_text" {
  type    = bool
  default = true
}

variable "initdb" {
  type = object({
    database = optional(string, "postgresql")
    owner    = optional(string, "admin")
  })
  description = "Database created at bootstrap and the role owning it."
  default     = {}
}

# Passed through verbatim to Cluster.spec.affinity. Accepts nodeSelector, nodeAffinity,
# tolerations, topologyKey — see the clusters.postgresql.cnpg.io CRD.
variable "affinity" {
  type    = any
  default = {}
}

variable "storage" {
  type = object({
    size          = optional(string, "8Gi")
    storage_class = optional(string, null)
  })
  default = {}
}

variable "resources" {
  type        = any
  description = "Requests and limits of the instance Pod. Equal values give it Guaranteed QoS."
  default = {
    requests = { cpu = "100m", memory = "512Mi" }
    limits   = { cpu = "1", memory = "512Mi" }
  }
}

variable "max_connections" {
  type    = number
  default = 50
}
