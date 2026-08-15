variable "domain" {
  type        = string
  description = "Internal DNS suffix for this cluster, e.g. lab.internal."
}

variable "argocd" {
  type = object({
    namespace  = optional(string, "argocd")
    plain_text = optional(bool, true)
  })
  description = "Where ApplicationSets are created, and how the provider reaches Argo CD."
  default     = {}
}

variable "gateway_namespace" {
  type        = string
  description = "Namespace holding the Gateway whose listeners reference certificate Secrets."
  default     = null
}

variable "metrics" {
  type = object({
    enabled = optional(bool, false)
  })
  description = "Whether this cluster has the Prometheus-operator CRDs and a collector."
  default     = {}
}
