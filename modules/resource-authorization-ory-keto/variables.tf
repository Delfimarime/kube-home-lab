variable "namespace" {
  type        = string
  description = "Where the store and its Secret go."

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a DNS-1123 label."
  }
}

# Where the store keeps its tuples. There is no embedded fallback worth running: the tuples *are*
# the authorization state, and a store that loses them on restart is one whose answers cannot be
# trusted between deployments.
#
# **Narrower than the shared database contract, and deliberately.** The store reads one `DSN`
# environment variable from a Secret and takes nothing else — so the host, the database name and
# the sslmode are all *inside* that string. Taking a `host_port` here would be a second statement
# of something the credential already carries, and nothing would compare the two.
# The key is not an input either: the chart hard-codes `dsn`, so naming it would be a knob with
# exactly one correct setting, which every caller would have to write down and nothing would read.
variable "database_secret_name" {
  type        = string
  default     = null
  description = "The Secret holding the store's connection string under `dsn`. Null renders an empty one here, named keto-db-credentials."
}

# Who may reach the write port.
#
# **Required, and empty is not a value.** The chart this module renders will happily produce no
# NetworkPolicy — a configuration it supports and this module does not, because nothing
# authenticates a caller on that port: reaching it *is* the permission, so leaving it open to every
# pod is leaving the permission graph writable by everything in the cluster. Refusing at plan time
# is the only place that can be said before it is true.
#
# These are selectors rather than references to other modules. The workloads they name are
# applications this repository does not deploy, so the composing root states them and this module
# stays ignorant of what it is admitting.
variable "write_access_from" {
  type = map(object({
    namespace = string
    labels    = map(string)
  }))
  description = "The workloads permitted to reach the write port, one entry each, keyed by a name that says who they are."

  # A store nothing may write to is a store nobody can configure — every tuple has to be created by
  # something, and refusing here is earlier than discovering it when the first grant fails.
  validation {
    condition     = length(var.write_access_from) > 0
    error_message = "write_access_from must name at least one workload: a store nothing may write to is one nobody can configure."
  }

  validation {
    condition     = alltrue([for k, w in var.write_access_from : length(w.labels) > 0])
    error_message = "every write_access_from entry needs at least one label: an empty selector admits every pod in that namespace, which is a wider door than naming a namespace was meant to open."
  }

  validation {
    condition     = alltrue([for k, w in var.write_access_from : can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", w.namespace))])
    error_message = "every write_access_from namespace must be a DNS-1123 label."
  }
}

# The permission model — the schema of the graph, not its data. Two ways to say it, and never both.
#
# `content` is a model somebody wrote, passed through verbatim; the caller reads it from a file,
# because it is source code in a language that is not this one. `namespaces` is the same model
# described as data and generated here.
#
# **Null takes the chart's default**, which declares one subject namespace and nothing else — a
# working store that authorizes nobody. That is the right state to ship in until there is an
# application to describe, and it fails closed: with no object types and no permits there is no
# rule for a derived question to match. Null rather than an empty string, because an empty model is
# a parse error at boot — "no model" and "the empty model" are different things and only one runs. **The generated form is deliberately a subset**: one level
# of composition, three kinds of term, no negation. A model that needs more than that has outgrown
# it and takes `content` — which is why both exist rather than one replacing the other.
#
# What generating buys is checking. A model written by hand is parsed by nothing until the store
# reads it at boot; the validations below run at plan time, and the last of them catches a defect
# upstream had to fix because it failed open — a name declared as both a relation and a permit in
# one namespace used to shadow silently and make checks return wrong answers.
variable "model" {
  type = object({
    content = optional(string)
    namespaces = optional(map(object({
      relations = optional(map(list(string)), {})
      permits = optional(map(object({
        any_of = optional(list(object({
          relation = optional(string)
          permit   = optional(string)
          traverse = optional(object({
            relation = string
            permit   = string
          }))
        })))
        all_of = optional(list(object({
          relation = optional(string)
          permit   = optional(string)
          traverse = optional(object({
            relation = string
            permit   = string
          }))
        })))
      })), {})
    })))
  })
  default     = null
  description = "The permission model: `content` for one written by hand, `namespaces` for one described as data. Null ships the chart's default, which grants nothing."

  validation {
    condition     = var.model == null ? true : !(var.model.content != null && var.model.namespaces != null)
    error_message = "model.content and model.namespaces are two ways to say the same thing: set one. Null asks for the default."
  }

  validation {
    condition     = try(var.model.content, null) == null ? true : length(trimspace(var.model.content)) > 0
    error_message = "model.content must be non-empty: an empty file is a parse error at boot, and null is how you ask for the default."
  }

  # A relation's target must be a namespace this model declares. Nothing else can resolve it: the
  # store has no namespaces but these.
  validation {
    condition = alltrue([
      for ns, spec in coalesce(try(var.model.namespaces, null), {}) : alltrue([
        for r, types in spec.relations : alltrue([
          for t in types : contains(keys(var.model.namespaces), split("#", t)[0])
        ])
      ])
    ])
    error_message = "a relation names a target namespace this model does not declare."
  }

  # `Group#members` is a subject set, and it is only meaningful if `Group` actually has `members`.
  validation {
    condition = alltrue([
      for ns, spec in coalesce(try(var.model.namespaces, null), {}) : alltrue([
        for r, types in spec.relations : alltrue([
          for t in types : length(split("#", t)) == 1 ? true : contains(
            keys(var.model.namespaces[split("#", t)[0]].relations), split("#", t)[1]
          )
        ])
      ])
    ])
    error_message = "a subject set names a relation its target namespace does not have."
  }

  # A permission is either a disjunction or a conjunction. Both, or neither, is not an expression.
  validation {
    condition = alltrue([
      for ns, spec in coalesce(try(var.model.namespaces, null), {}) : alltrue([
        for p, e in spec.permits : (e.any_of != null) != (e.all_of != null)
      ])
    ])
    error_message = "every permit needs exactly one of any_of or all_of."
  }

  # Each term is one of the three things a term can be.
  validation {
    condition = alltrue([
      for ns, spec in coalesce(try(var.model.namespaces, null), {}) : alltrue([
        for p, e in spec.permits : alltrue([
          for t in coalesce(e.any_of, e.all_of, []) :
          length([for f in [t.relation, t.permit, t.traverse] : f if f != null]) == 1
        ])
      ])
    ])
    error_message = "every term is exactly one of relation, permit or traverse."
  }

  # A term referencing something that is not there is a permission that silently never grants.
  validation {
    condition = alltrue([
      for ns, spec in coalesce(try(var.model.namespaces, null), {}) : alltrue([
        for p, e in spec.permits : alltrue([
          for t in coalesce(e.any_of, e.all_of, []) : (
            t.relation != null ? contains(keys(spec.relations), t.relation) :
            t.permit != null ? contains(keys(spec.permits), t.permit) :
            contains(keys(spec.relations), t.traverse.relation)
          )
        ])
      ])
    ])
    error_message = "a permit references a relation or permit its own namespace does not declare."
  }

  # **The one that fails open.** Upstream shadowed silently here and returned wrong answers until a
  # 2026 release started rejecting it; refusing at plan time is earlier than refusing at boot.
  validation {
    condition = alltrue([
      for ns, spec in coalesce(try(var.model.namespaces, null), {}) :
      length(setintersection(keys(spec.relations), keys(spec.permits))) == 0
    ])
    error_message = "a name is declared as both a relation and a permit in one namespace, which shadows."
  }
}

variable "metrics" {
  type = object({
    enabled = optional(bool, false)
    tenant  = optional(string)
  })
  default     = {}
  description = "Whether the cluster scrapes, and which tenant this workload's telemetry belongs to."
}

# **There is no chart-version input.** The chart this module renders is this repository's, read
# from git at `git_repository.revision` — so the revision is the pin, and a `chart_version` here
# would be a number nothing reads. The version of the *upstream* store chart is pinned where it is
# resolved, in `helm/ory-keto/Chart.yaml`'s dependency.

variable "argocd" {
  type = object({
    namespace = optional(string, "argocd")
  })
  default     = {}
  description = "Where the ApplicationSet object is created."
}

variable "git_repository" {
  type = object({
    url      = string
    revision = string
  })
  description = "This repository, and the revision Argo CD reads its charts at."
}
