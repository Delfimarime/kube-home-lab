# Where the stores, the collector and the object-store credentials live. One namespace: the
# collector writes to the stores over cluster DNS and a Secret is namespaced, so splitting them
# would buy nothing and cost another copy of an access key somebody types in by hand.
variable "namespace" {
  type        = string
  description = "Namespace for the stores, the collector and the Secrets holding the object stores' access keys."
  default     = "observability"
}

# Only the namespace. Nothing about *reaching* Argo CD is a module input.
variable "argocd" {
  type = object({
    namespace = optional(string, "argocd")
  })
  description = "Where the ApplicationSet is created."
  default     = {}
}

# The name this cluster's telemetry is labelled with, on every metric, log line and span the
# collector produces. It is an environment's own fact and there is no defensible default: two
# clusters both calling themselves "default" produce series that differ in nothing a query can see,
# and the mistake is only visible once both are being read side by side.
variable "cluster_name" {
  type        = string
  description = "The cluster label attached to everything this module collects."

  validation {
    condition     = length(var.cluster_name) > 0
    error_message = "cluster_name must be set: it labels every metric, log line and span, and an empty value makes two environments indistinguishable once their data is read together."
  }
}

# The object store every component uses unless it says otherwise. Required, and there is no
# filesystem fallback: an optional backend means the unsupported configuration is what an
# environment gets by forgetting an input, and it would be two sets of values and two failure
# modes in a module whose whole design is about degrading along one axis — which signals are
# collected — and not two.
#
# The credential passes by reference: a Secret name and the two keys inside it, never a value.
#
#   secret_name null  this module renders the Secret itself, in its own namespace, with both keys
#                     present and empty, and the Application ignores its contents from then on
#   secret_name set   an existing Secret this module only reads, and neither creates nor prunes
#
# **There is no bucket here, and that is the point.** A bucket belongs to exactly one store, so
# there is nowhere in this input to name one for all of them — which is what makes two stores
# sharing a bucket something an environment cannot say rather than something it must remember not
# to say.
#
# The key names default to what the object store publishes, so an environment that took those
# defaults on both sides has nothing to write here. Whatever they end up as is what an operator
# patches into the Secret.
variable "object_storage" {
  type = object({
    endpoint       = string
    region         = optional(string, "us-east-1")
    secret_name    = optional(string)
    access_key_key = optional(string, "RUSTFS_ACCESS_KEY")
    secret_key_key = optional(string, "RUSTFS_SECRET_KEY")

    # Not part of the address: the endpoint is a host and a port, and whether the hop to it is
    # plaintext is a separate fact. In-cluster it is; a store pointed somewhere off the cluster
    # almost certainly is not, and has to say so.
    insecure = optional(bool, true)
  })
  description = "The S3-compatible endpoint every component writes to unless it carries its own, its region, and the access key by reference."

  validation {
    condition     = can(regex("^[a-z0-9.-]+:[0-9]+$", var.object_storage.endpoint))
    error_message = "object_storage.endpoint must be a host and a port, e.g. \"s3-svc.object-storage.svc.cluster.local:9000\" — no scheme, because whether the hop speaks TLS is object_storage.insecure and not part of the address."
  }

  validation {
    condition     = var.object_storage.secret_name == null || can(regex("^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$", coalesce(var.object_storage.secret_name, "x")))
    error_message = "object_storage.secret_name must be a lower-case DNS subdomain name, e.g. \"object-storage-credentials\"."
  }

  validation {
    condition     = var.object_storage.access_key_key != var.object_storage.secret_key_key
    error_message = "object_storage.access_key_key and object_storage.secret_key_key must differ: they are two keys in one Secret, and one name cannot hold both halves of an access key pair."
  }
}

# **One block per signal, and the block's presence is what ships the store.** There is no flag
# beside this saying whether to collect a signal, because a flag and the configuration it claims
# to describe are two things that can disagree — set true with no bucket named, planning clean,
# syncing clean, and failing on the first write. Here the configuration *is* the switch, so that
# state cannot be written down.
#
# Reading one entry tells you whether that signal is collected, where it lands and how long it is
# kept. The only thing about a signal that lives elsewhere is its per-tenant ceilings, which are
# per *tenant* and belong with the tenants.
#
#   bucket          required, and there is no global equivalent at any level. One bucket belongs
#                   to one store; two components may not name the same one at the same endpoint.
#   retention       optional → var.retention.default. Lands in this store's own retention limit.
#   object_storage  optional. **Replaces** the top-level block outright — see below.
#
# **An override replaces and never merges, and this is the sharp edge of the whole module.** A
# component that sets only `endpoint` does not inherit the region or the credential above it; it
# gets the field defaults, so a top-level region of "af-south-1" yields "us-east-1" underneath and
# the symptom is a signature mismatch that names neither a region nor an input.
#
# Merging would be worse and quieter. A partial override reads as "like the others, but over
# there", and the field it most easily fails to mention is the credential — so a store would be
# pointed at somebody else's endpoint while being handed this cluster's access key, which plans
# clean and returns 403 forever. Replacement forces a component that writes elsewhere to state
# everything about writing elsewhere, at the one moment somebody is already thinking about it.
variable "components" {
  type = object({
    metrics = optional(object({
      bucket    = string
      retention = optional(string)
      object_storage = optional(object({
        endpoint       = string
        region         = optional(string, "us-east-1")
        secret_name    = optional(string)
        access_key_key = optional(string, "RUSTFS_ACCESS_KEY")
        secret_key_key = optional(string, "RUSTFS_SECRET_KEY")
        insecure       = optional(bool, true)
      }))
    }))

    logs = optional(object({
      bucket    = string
      retention = optional(string)
      object_storage = optional(object({
        endpoint       = string
        region         = optional(string, "us-east-1")
        secret_name    = optional(string)
        access_key_key = optional(string, "RUSTFS_ACCESS_KEY")
        secret_key_key = optional(string, "RUSTFS_SECRET_KEY")
        insecure       = optional(bool, true)
      }))
    }))

    traces = optional(object({
      bucket    = string
      retention = optional(string)
      object_storage = optional(object({
        endpoint       = string
        region         = optional(string, "us-east-1")
        secret_name    = optional(string)
        access_key_key = optional(string, "RUSTFS_ACCESS_KEY")
        secret_key_key = optional(string, "RUSTFS_SECRET_KEY")
        insecure       = optional(bool, true)
      }))
    }))
  })
  description = "One optional block per signal; a block's presence ships that store. Each names its own bucket, and may name its own object store."

  validation {
    condition = length([
      for c in [var.components.metrics, var.components.logs, var.components.traces] : c if c != null
    ]) > 0
    error_message = "components must carry at least one of metrics, logs or traces: with all three absent this module runs a collector with nowhere to write."
  }

  validation {
    condition = alltrue([
      for signal, c in {
        metrics = var.components.metrics
        logs    = var.components.logs
        traces  = var.components.traces
      } : c == null || length(trimspace(try(c.bucket, ""))) > 0
    ])
    error_message = "every component must name a non-empty components.<signal>.bucket: a store is only reachable through the bucket it writes to, and there is no bucket set anywhere else for it to fall back on."
  }

  # Two stores writing into one bucket is not a configuration anybody wants, and the input surface
  # makes it hard rather than impossible: a bucket can only be named inside a component, so the
  # only way to collide is to type the same name twice. Endpoint and bucket together are what
  # identify a place to write, so the same name at two different endpoints is two different
  # buckets and is allowed.
  validation {
    condition = length(distinct([
      for signal, c in {
        metrics = var.components.metrics
        logs    = var.components.logs
        traces  = var.components.traces
      } : "${c.object_storage == null ? var.object_storage.endpoint : c.object_storage.endpoint}/${c.bucket}"
      if c != null
      ])) == length([
      for signal, c in {
        metrics = var.components.metrics
        logs    = var.components.logs
        traces  = var.components.traces
      } : signal
      if c != null
    ])
    error_message = format(
      "two components name the same bucket at the same endpoint, and a bucket belongs to exactly one store. The endpoint-and-bucket pairs given were: %s. Give each of components.metrics.bucket, components.logs.bucket and components.traces.bucket a name of its own, or point one of them at its own object_storage.endpoint.",
      join(", ", [
        for signal, c in {
          metrics = var.components.metrics
          logs    = var.components.logs
          traces  = var.components.traces
        } : "${signal} => ${c.object_storage == null ? var.object_storage.endpoint : c.object_storage.endpoint}/${c.bucket}"
        if c != null
      ])
    )
  }

  # An override says where a store writes, so the field naming that place is the one it cannot
  # leave out. It is also the only part of the sharp edge above that can be caught here at all —
  # nothing can tell an intentionally-defaulted region from a forgotten one.
  validation {
    condition = alltrue([
      for signal, c in {
        metrics = var.components.metrics
        logs    = var.components.logs
        traces  = var.components.traces
      } :
      c == null || c.object_storage == null ||
      can(regex("^[a-z0-9.-]+:[0-9]+$", try(c.object_storage.endpoint, "")))
    ])
    error_message = "components.<signal>.object_storage.endpoint must be a host and a port, e.g. \"s3.remote.example:9000\" — an override exists to say where that store writes instead, so the address is the one field it cannot omit, and it carries no scheme because whether the hop speaks TLS is object_storage.insecure."
  }

  validation {
    condition = alltrue([
      for c in [var.components.metrics, var.components.logs, var.components.traces] :
      c == null || c.object_storage == null ||
      try(c.object_storage.access_key_key, "a") != try(c.object_storage.secret_key_key, "b")
    ])
    error_message = "components.<signal>.object_storage.access_key_key and secret_key_key must differ: they are two keys in one Secret, and one name cannot hold both halves of an access key pair."
  }

  validation {
    condition = alltrue([
      for c in [var.components.metrics, var.components.logs, var.components.traces] :
      c == null || c.object_storage == null || c.object_storage.secret_name == null ||
      can(regex("^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$", coalesce(try(c.object_storage.secret_name, null), "x")))
    ])
    error_message = "components.<signal>.object_storage.secret_name must be a lower-case DNS subdomain name, e.g. \"tempo-remote-credentials\"."
  }

  validation {
    condition = alltrue([
      for c in [var.components.metrics, var.components.logs, var.components.traces] :
      c == null || c.retention == null || can(regex("^[0-9]+[smh]$", coalesce(c.retention, "0h")))
    ])
    error_message = "components.<signal>.retention must be a whole number of seconds, minutes or hours, e.g. \"720h\" — the three stores each spell retention differently and this is the one spelling all of them accept."
  }
}

# How long things are kept, at the one level that spans every signal. Both fields are about the
# same subject, so they are one object rather than two inputs sharing a prefix — the next thing
# this module has to say about retention goes here without renaming anything.
#
#   default       what a component is kept for when it says nothing. A default and never a
#                 ceiling: a component's own value overrides it, and a tenant's own value overrides
#                 that. It exists so an environment writes its number once instead of three times,
#                 and the two levels below it are the ones every store already had.
#
#   unattributed  how long a write that carried no tenant header is kept. That tenant is this
#                 module's own invention rather than anything a caller may name, which is why its
#                 number sits here rather than in a component or beside a tenant — it is one tenant
#                 across every store, exactly as `default` is one number across every component.
#
#                 Short deliberately. It exists so a forgotten header shows up as something filling
#                 rather than as a silent loss, and the tenant nobody meant to write to should not
#                 be the one holding data longest.
variable "retention" {
  type = object({
    default      = optional(string, "168h")
    unattributed = optional(string, "24h")
  })
  description = "The retention every component inherits unless it names its own, and how long a write carrying no tenant is kept."
  default     = {}

  validation {
    condition = alltrue([
      for d in [var.retention.default, var.retention.unattributed] :
      can(regex("^[0-9]+[smh]$", d))
    ])
    error_message = "retention.default and retention.unattributed must be a whole number of seconds, minutes or hours, e.g. \"168h\" — the three stores each spell retention differently and this is the one spelling all of them accept."
  }
}

# The shared contract, unchanged in shape. It exposes the OTLP receiver and nothing else — no
# store is ever routed, whatever this is set to.
#
# What may reach the hostname once it resolves is the listener's business rather than this
# module's: `section_name` pointing at a listener demanding a client certificate is the whole of
# how this module asks for mTLS, and pointing it at an ordinary TLS listener is equally valid. The
# posture that does not depend on which was chosen is that the surface is write-only — telemetry
# goes in, nothing comes back out, and there is no read path through this host.
variable "gateway" {
  type = object({
    name         = string
    namespace    = string
    hostname     = string
    section_name = optional(string)
  })
  description = "The Gateway, listener and hostname the OTLP receiver is exposed on. null is not exposed."
  default     = null
}

# The tenants this module knows about, and the ceilings it gives them. **Naming a tenant here does
# not create it and leaving one out does not refuse it**: any caller may write under any name, and
# a name absent from this map lands under its store's own limits — which are now a number somebody
# chose rather than an unbounded default.
#
# One shape across three stores, which is possible only because the metrics store's chart is this
# repository's own and could be written to match the other two rather than expressing the same idea
# a third way. Every limit is optional; an omitted one leaves the store's own limit in place.
variable "tenants" {
  type = map(object({
    metrics = optional(object({
      limits = optional(object({
        ingestion_rate       = optional(number) # samples per second
        ingestion_burst_size = optional(number) # samples
        max_series           = optional(number) # active series held for this tenant
        retention            = optional(string)
      }), {})
    }), {})

    logs = optional(object({
      limits = optional(object({
        ingestion_rate_mb       = optional(number) # MB per second
        ingestion_burst_size_mb = optional(number) # MB
        max_streams             = optional(number) # active streams held for this tenant
        retention               = optional(string)
      }), {})
    }), {})

    traces = optional(object({
      limits = optional(object({
        ingestion_rate_bytes = optional(number) # bytes per second
        max_traces           = optional(number) # live traces held for this tenant
        retention            = optional(string)
      }), {})
    }), {})
  }))
  description = "Tenants to bound, keyed by the value callers send in X-Scope-OrgID. Limits and retention per signal."

  validation {
    condition     = length(var.tenants) > 0
    error_message = "tenants must name at least one tenant: every read and write carries a tenant header, so a store with no tenant bounded anywhere has nothing this module can size."
  }

  # A write arriving with no header is stored under this name rather than refused, so it is a name
  # this module writes and not one a caller may claim. Letting it be listed would mean the same
  # string described both "telemetry nobody had to label" and "telemetry somebody forgot to", with
  # one retention between them.
  validation {
    condition     = !contains(keys(var.tenants), "unattributed")
    error_message = "\"unattributed\" is reserved: it is where a write carrying no tenant header is kept, so that a forgotten header shows up as a filling tenant rather than as data the collector accepted and the store threw away. Name this tenant something else."
  }

  # The stores' own telemetry is written under a name this module stamps on its own workloads, so a
  # caller listing it would be describing writes it does not make and cannot change.
  validation {
    condition     = !contains(keys(var.tenants), "telemetry-storage")
    error_message = "\"telemetry-storage\" is reserved: it is what this module's own workloads — the stores, and the collector where it reports on itself — are collected as, stamped on them from inside this module. Name this tenant something else."
  }

  validation {
    condition = alltrue(flatten([
      for name, t in var.tenants : [
        for d in [t.metrics.limits.retention, t.logs.limits.retention, t.traces.limits.retention] :
        d == null || can(regex("^[0-9]+[smh]$", coalesce(d, "0h")))
      ]
    ]))
    error_message = "every tenants.<name>.<signal>.limits.retention must be a whole number of seconds, minutes or hours, e.g. \"168h\" — the three stores each spell retention differently and this is the one spelling all of them accept."
  }

  validation {
    condition = alltrue([
      for name, _ in var.tenants :
      can(regex("^[a-zA-Z0-9][a-zA-Z0-9._-]*$", name))
    ])
    error_message = "a tenant name must be a plain identifier — letters, digits, dot, dash and underscore — because it travels as an HTTP header value on every read and write."
  }
}

# What this module's *own* writes are labelled with. Scraped metrics and tailed log lines arrive
# with no request behind them and therefore no header to carry forward, so they are stamped with
# this instead.
#
# **It is not a fallback for callers.** A push that omits the header is kept under a different name
# on purpose: one is telemetry nobody had to label, the other is telemetry somebody forgot to, and
# a single name for both would hide the second inside the first.
variable "default_tenant" {
  type        = string
  description = "The tenant scraped metrics and tailed logs are written as. Must be one of the tenants."

  validation {
    condition     = contains(keys(var.tenants), var.default_tenant)
    error_message = "default_tenant must name one of the keys in tenants: this module's own scraping is written under it, and a name absent from the map would be collected under no ceiling at all."
  }
}

# Pinned exactly, so an upgrade is a deliberate edit and a chart's values schema cannot change
# underneath this module silently.
variable "prometheus_operator_crds" {
  type = object({
    chart_version = optional(string, "31.0.1")
  })
  description = "The Prometheus-operator CRD bundle, which the collector reads scrape configuration from."
  default     = {}
}

# The metrics store's chart is this repository's own, so what is pinned is the image rather than a
# chart version — the chart's revision is git_repository.revision, like every other chart here.
variable "mimir" {
  type = object({
    image_tag = optional(string, "3.1.4")
  })
  description = "The metrics store's image."
  default     = {}
}

variable "loki" {
  type = object({
    chart_version = optional(string, "7.3.0")
  })
  description = "The log store's chart."
  default     = {}
}

# The trace store's chart is marked deprecated by its authors and is still the right pin: the only
# maintained alternative deploys the distributed topology, which is a dozen pods for a deployment
# whose entire design is one. Revisit when a maintained single-binary chart exists, not before.
variable "tempo" {
  type = object({
    chart_version = optional(string, "1.24.4")
  })
  description = "The trace store's chart."
  default     = {}
}

# A per-component escape hatch, merged over what this module builds, and keyed by signal like
# everything else here. **Merged one level deep**: a key present in both is merged when both sides
# are maps and replaced otherwise, so `logs = { loki = { limits_config = {...} } }` replaces that
# store's whole `loki` block, while `logs = { serviceMonitor = {...} }` sits beside it.
#
# It exists because three upstream charts move at their own pace and a values key this module does
# not model yet should not be a reason to edit this module. It is not the place to configure
# anything the inputs above already decide — storage, retention, tenancy and exposure are inputs,
# and setting one of them twice is how the two come to disagree.
variable "values" {
  type = object({
    metrics   = optional(any, {})
    logs      = optional(any, {})
    traces    = optional(any, {})
    collector = optional(any, {})
  })
  description = "Per-signal values merged over this module's own, one level deep. `collector` is the wrapped collector chart."
  default     = {}
}

# Two of the charts this module renders live in this repository rather than in a chart registry —
# the metrics store's, and the wrapper adding a route to the collector — so every environment
# shipping this module must have this repository registered as a source in its Argo CD.
#
# The paths are not inputs: this module knows where its own charts are, and an input for one would
# be a knob whose only correct setting is the one already in locals.
variable "git_repository" {
  type = object({
    url      = optional(string, "git@github.com:Delfimarime/kube-home-lab.git")
    revision = optional(string, "main")
  })
  description = "The repository Argo CD reads this repo's own charts from, and the revision it reads them at."
  default     = {}
}
