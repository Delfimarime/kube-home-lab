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
    size  = optional(string, "20Gi")
    class = optional(string, "local-path")
  })
  description = "The volume behind every bucket: how big, and from which StorageClass."
  default     = {}
  validation {
    condition     = can(regex("^[0-9]+(Mi|Gi|Ti)$", var.storage.size))
    error_message = "storage.size must be a Kubernetes quantity in Mi, Gi or Ti, e.g. \"20Gi\" — a value the API server rejects fails at sync time rather than here."
  }
}

# **Where this pod is allowed to run, and it decides where the data lives.** With a StorageClass
# that binds on first use — which is the default here — the claim is created against whichever
# node the pod was scheduled onto, and it stays there. Every later scheduling decision is then
# already made: the pod goes back to the node holding its volume or it does not start. So this is
# not a preference about placement, it is the one chance to choose which machine holds every
# stored signal.
#
# Three fields because there are three separate ways to be wrong about that, and they are one
# object because they are one subject:
#
#   node_selector  the flat answer. Labels that must all match, and nothing else is expressible —
#                  no alternatives, no ordering, no negation.
#   affinity       the same question with the expressiveness the flat form lacks: a set of
#                  acceptable nodes rather than one, a preference that degrades instead of
#                  failing, or a match on anything a label selector can say. Passed through as
#                  given, because this is the Kubernetes API's own shape and restating it here
#                  would be a second copy to drift.
#   tolerations    what makes either of the above reachable. A node picked deliberately is often
#                  picked *because* it is set apart, and on a small cluster the machine somebody
#                  wants this on is frequently the control-plane node, which carries a taint that
#                  refuses ordinary pods. Naming that node without tolerating its taint produces a
#                  pod that is Pending forever and an event nobody reads — the selector looks
#                  correct in the manifest and matches a node that will not take it.
#
# Setting node_selector and affinity together is legal and both apply; there is no rule here that
# refuses it, because a caller narrowing with one and expressing an alternative with the other is
# doing something coherent.
variable "placement" {
  type = object({
    node_selector = optional(map(string))
    affinity      = optional(any)
    tolerations   = optional(list(any))
  })
  description = "Which node this pod may run on — and therefore which machine holds every stored signal, because the volume follows the pod that first claimed it."
  default     = {}

  # The three keys the API server accepts, checked here so a typo is a plan-time message naming
  # the input rather than a sync-time rejection of a manifest nobody is reading at the time. An
  # unknown key is refused by the API server, so the Application simply stops progressing.
  validation {
    condition = var.placement.affinity == null || alltrue([
      for k in keys(var.placement.affinity) :
      contains(["nodeAffinity", "podAffinity", "podAntiAffinity"], k)
    ])
    error_message = "placement.affinity may only carry nodeAffinity, podAffinity or podAntiAffinity: any other key is rejected by the API server, which stops the Application syncing rather than reporting a bad input."
  }
}

# **What a caller pins here is the image, not a chart version**, and the difference is the whole
# reason this input reads the way it does. The chart rendering this workload is published from
# this repository, so its version is decided by whoever edits it and moves with the commit Argo CD
# reads — `git_repository.revision` already pins that. What no commit of this repository decides
# is which server build runs, and that is the thing an environment upgrades on its own schedule
# and rolls back on a bad release.
#
# The tag is a timestamped release string rather than a semantic version, so it sorts
# chronologically and nothing about it can be compared for compatibility — which is precisely why
# it is pinned exactly instead of floated. `-distroless` is part of the tag and not a suffix that
# can be dropped: the plain tag is a different image with a shell in it.
variable "silo" {
  type = object({
    image_tag = optional(string, "RELEASE.2026-09-03T13-18-01Z-distroless")
  })
  description = "The server image the chart runs. A timestamped release tag, pinned exactly."
  default     = {}

  validation {
    condition     = length(var.silo.image_tag) > 0
    error_message = "silo.image_tag must name a tag: an empty string leaves the chart pinning nothing, and what runs then is whatever the registry last called latest."
  }
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
# follow one number per surface; what the process actually binds follows the same one. Setting one
# without the other produces a Service pointing at a port nothing is listening on, and a pod that
# never passes its readiness probe.
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

  # **The two hostnames must differ, and this is not a stylistic rule.** A routed surface is told
  # its own external address so that the links it generates — a redirect back from the console, a
  # presigned URL from the API — point at something reachable from outside rather than at a
  # cluster-internal Service name. Give both surfaces one hostname and the process cannot tell
  # which of the two a request was for: the console's redirect lands on the API and the API's
  # signed URLs point at the console. It fails as an authentication error on a URL that looks
  # correct, which is why it is caught here instead.
  validation {
    condition = (
      var.services.api.hostname == null ||
      var.services.management_console.hostname == null ||
      var.services.api.hostname != var.services.management_console.hostname
    )
    error_message = "services.api.hostname and services.management_console.hostname must differ: the two surfaces advertise their own external addresses, and one hostname cannot be both."
  }
}

# **The size of the box the process is told it is in, which is not the same as the size of the box
# it is actually in — and every field here exists because the difference is what breaks.**
#
# Two independent auto-sizing mechanisms read the machine rather than the cgroup:
#
#   The server sets its own ceiling on concurrent API requests from the RAM it observes, roughly
#   three quarters of total memory divided by 2MiB per request. On a node with far more memory
#   than the container is allowed, that arrives at a number of in-flight requests whose buffers
#   cannot fit in the limit — so the ceiling that exists to prevent memory exhaustion is itself
#   set high enough to cause it. `api_requests_max` states the number instead of letting it be
#   derived from the wrong quantity.
#
#   The Go runtime grows the heap until a collection is worth doing, and what it considers worth
#   doing is a fraction of what it believes is available. Nothing in that calculation knows about
#   a cgroup limit, so the heap grows past it and the kernel kills the process — with no panic, no
#   stack and no log line, because the process is not told. `go_memory_limit` is the soft ceiling
#   that makes the runtime collect before the kernel intervenes, and it sits below the limit
#   rather than at it, because a Go process needs headroom above the heap for stacks and for the
#   allocation that triggers the collection. Roughly 83% of the limit leaves that headroom.
#
# `go_max_procs` is the third: the runtime sizes its scheduler from the node's CPU count, so a
# container with a fractional CPU quota gets as many parallel threads as the node has cores, and
# spends its quota being descheduled mid-collection instead of running.
#
# **A memory limit with no `go_memory_limit` is not a conservative configuration, it is the one that
# gets OOM-killed** — the limit tells the kernel when to kill and tells the runtime nothing — so
# the chart refuses to render that pairing and the validation below refuses to hand it over.
variable "resources" {
  type = object({
    requests = optional(object({
      cpu    = optional(string, "200m")
      memory = optional(string, "512Mi")
    }), {})
    limits = optional(object({
      cpu    = optional(string, "2000m")
      memory = optional(string, "2Gi")
    }), {})
    go_memory_limit  = optional(string, "1700MiB")
    go_max_procs     = optional(number, 2)
    api_requests_max = optional(number, 128)
  })
  description = "What the container is allowed, and what the process is told it is allowed. The second is not derived from the first by anything, which is why both are here."
  default     = {}

  # Mi or Gi only. A memory quantity is also accepted by Kubernetes as `2G`, `2000000000` or `2e9`,
  # and those are decimal — a caller who writes `2G` meaning two gibibytes is short by 7%, and
  # then computes a `go_memory_limit` against the number they meant rather than the one in effect.
  # Restricting the unit removes the arithmetic rather than documenting it.
  validation {
    condition = alltrue([
      for q in [var.resources.requests.memory, var.resources.limits.memory] :
      can(regex("^[0-9]+(Mi|Gi)$", q))
    ])
    error_message = "resources.requests.memory and resources.limits.memory must be quantities in Mi or Gi, e.g. \"512Mi\" or \"2Gi\" — decimal units are a different number than the one they are usually meant to be."
  }

  # The invariant stated rather than left to be inferred from the rule above. That rule forbids a
  # blank memory limit today, so this one cannot fire today; it is here because the pairing is the
  # actual requirement — a limit the kernel enforces and a ceiling the runtime respects arrive
  # together or the process is killed — and relaxing the quantity rule must not quietly relax
  # this one too.
  validation {
    condition     = length(var.resources.limits.memory) == 0 || length(var.resources.go_memory_limit) > 0
    error_message = "resources.go_memory_limit must be set whenever resources.limits.memory is: a memory limit with no runtime ceiling is the configuration that gets OOM-killed, because the limit tells the kernel when to kill and tells the runtime nothing."
  }

  # Both are counts and both are numbers here, though the container receives them as environment
  # variables and therefore as text. Zero is the value to refuse rather than the one to allow: a
  # scheduler with no threads and a server permitting no concurrent request are each a process
  # that starts and then serves nothing.
  validation {
    condition     = var.resources.go_max_procs > 0 && var.resources.api_requests_max > 0
    error_message = "resources.go_max_procs and resources.api_requests_max must both be greater than zero: they are counts, and a process told it may use none of something starts cleanly and then does no work."
  }
}

# Where Argo CD reads this repository's own charts from. This module renders one of them for the
# workload itself, and a second for the placeholder Secret when it is rendering one — so every
# environment using this module must have this repository registered as a source.
#
# The path each chart sits at is not an input: this module knows where its own charts are, and an
# input for one would be a knob whose only correct setting is the one already here.
variable "git_repository" {
  type = object({
    url      = optional(string, "git@github.com:Delfimarime/kube-home-lab.git")
    revision = optional(string, "main")
  })
  description = "The repository Argo CD reads this repo's own charts from, and the revision it reads them at."
  default     = {}
}
