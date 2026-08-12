variable "argocd_namespace" {
  type        = string
  description = "Namespace the ApplicationSet is created in."
  default     = "argocd"
}

variable "namespace" {
  type        = string
  description = "Existing namespace PostgreSQL runs in."
  default     = "storage"
}

# Names the StatefulSet, the Service and the generated credentials Secret — the chart sets
# fullnameOverride from it, so all three agree and outputs.tf can name them without asking
# the cluster.
variable "cluster_name" {
  type    = string
  default = "postgresql"
}

variable "argocd_plain_text" {
  type    = bool
  default = true
}

# The chart is in this repository, not a chart repository, so Argo CD reads it from git.
# Public repo, so no credential is registered in Argo CD for it.
variable "chart" {
  type = object({
    repo_url = optional(string, "https://github.com/Delfimarime/kube-home-lab.git")
    path     = optional(string, "dependencies/postgresql/helm")
    revision = optional(string, "main")
  })
  description = "Where Argo CD reads the chart from."
  default     = {}
}

variable "initdb" {
  type = object({
    database = optional(string, "postgresql")
    owner    = optional(string, "admin")
  })
  description = "Database created at bootstrap and the role owning it. Only read on an empty volume."
  default     = {}
}

# Passed through verbatim to the Pod spec, so this is plain Kubernetes affinity — the
# CloudNativePG Cluster CRD's own wrapper schema no longer applies.
variable "affinity" {
  type    = any
  default = {}
}

variable "service" {
  type = object({
    type      = optional(string, "ClusterIP")
    node_port = optional(number, null)
  })
  description = "How PostgreSQL is reachable. node_port is read only when type is NodePort, and k3s rejects anything outside 30000-32767 unless the apiserver was given a wider --service-node-port-range."
  default     = {}
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
