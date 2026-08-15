# Everything true of the cluster being addressed and not of another one. Supplied by a var file
# per environment; nothing here has a default that would be wrong somewhere else.

# The suffix every certificate this environment issues is named for. Internal only: there is no
# public DNS record and no ACME (cert-manager LOCAL-001).
variable "domain" {
  type        = string
  description = "Internal DNS suffix for this cluster, e.g. lab.internal."
}

# Where this cluster's Argo CD is, and the one connection field with no environment variable.
# `plain_text = true` matches how Argo CD is normally reached here: a port-forward, or an
# in-cluster address where TLS terminates elsewhere. A default, not a recommendation.
variable "argocd" {
  type = object({
    namespace  = optional(string, "argocd")
    plain_text = optional(bool, true)
  })
  description = "Where ApplicationSets are created, and how the provider reaches Argo CD."
  default     = {}
}

# k3s ships Traefik in kube-system, and its Gateway is what references the certificate Secrets.
# null means no ReferenceGrant, so a Gateway elsewhere cannot use them.
variable "gateway_namespace" {
  type        = string
  description = "Namespace holding the Gateway whose listeners reference certificate Secrets."
  default     = null
}

# ADR 016. True says this cluster has the Prometheus-operator CRDs *and* something reading them.
# Turning it on before `observability-storage-grafana-lgtm` ships produces ServiceMonitors no
# collector reads, and on a cluster without the CRDs, a sync that fails on an unknown kind.
variable "metrics" {
  type = object({
    enabled = optional(bool, false)
  })
  description = "Whether this cluster has the Prometheus-operator CRDs and a collector."
  default     = {}
}
