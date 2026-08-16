# The Secret's name, and the Application's. One string for both: an Application named for
# something other than what it renders is a name that has to be looked up to be understood.
variable "name" {
  type        = string
  description = "The Secret to render, and the name of the Application rendering it."

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$", var.name))
    error_message = "name must be a lower-case DNS subdomain name, e.g. \"object-storage-credentials\"."
  }
}

# The keys the Secret must carry, and the reason this module exists rather than each caller
# writing its own element.
#
# **They are the names the workload looks for, and getting them from anywhere else is the bug
# this prevents.** A key read through a `secretKeyRef` is whatever that chart calls it; a Secret
# consumed through `envFrom` becomes environment variables, so its keys must be the variable
# names themselves. Either way they belong to the consuming chart, so a caller passes the same
# values it builds its own configuration from.
variable "keys" {
  type        = list(string)
  description = "The keys the Secret carries, empty. The names the workload reads, not names chosen here."

  validation {
    condition     = length(var.keys) > 0
    error_message = "keys must name at least one key: a Secret with the right name and no keys fails at pod start, which reads as a broken module."
  }

  validation {
    condition     = length(var.keys) == length(distinct(var.keys))
    error_message = "keys must not repeat — a duplicate is a copy-paste that renders one key and hides the other."
  }
}

variable "namespace" {
  type        = string
  description = "Where the Secret goes. The consuming module's own namespace: a Secret is namespaced, and nothing here renders one into somebody else's."
}

# Which sync wave the Application belongs to. Defaults to the first, because a credential exists
# to be read by something that syncs after it — a workload that starts before its Secret is a
# crash loop that resolves itself, and looks exactly like a wrong value, which does not.
variable "wave" {
  type        = string
  description = "The Argo CD sync wave. Ahead of whatever reads the Secret."
  default     = "0"
}

# Where Argo CD reads this chart from. It lives in this repository rather than in a chart
# registry, so every environment rendering a credential must have this repository registered as a
# source.
#
# The path is not an input: this module knows where its own chart is, and an input for it would be
# a knob whose only correct setting is the one already here.
variable "git_repository" {
  type = object({
    url      = optional(string, "git@github.com:Delfimarime/kube-home-lab.git")
    revision = optional(string, "main")
  })
  description = "The repository Argo CD reads this chart from, and the revision it reads it at."
  default     = {}
}
