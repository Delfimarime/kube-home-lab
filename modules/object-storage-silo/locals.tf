locals {
  # The chart this module renders, published from this repository's own `helm/` tree rather than
  # owned by this module — so its values schema is the chart's and a second consumer is allowed.
  # A constant rather than an input: the only correct value is this one, and a caller able to
  # change it could only ever point an Application at a path that does not exist.
  chart_path = "helm/silo-standalone"

  # The Application's name, and the Helm release inside it. It names the protocol rather than the
  # product: the published address is what consumers are configured with, and swapping the
  # implementation should not be a re-configuration of every consumer.
  release = "s3"

  # **The Service's name, stated rather than derived, and the `-svc` is not a convention — it is
  # the name consumers already hold.** The chart this module now renders names every object from
  # `fullnameOverride`, so nothing appends a suffix any more and the obvious name would be plain
  # `s3`. It is spelled out in full here because the endpoint published below is built from it,
  # and that string is written into the configuration of every workload that stores anything.
  # Shortening it would be a rename of an address nothing warns about: each consumer keeps
  # resolving the old name until it is redeployed, and then fails to resolve anything.
  #
  # This module states the name and reads it back, rather than reproducing whatever rule the chart
  # would otherwise derive one by — a copy that goes stale the day the chart changes, and whose
  # only symptom is an address nothing answers on.
  service = "s3-svc"

  # The two keys the Secret carries, and they name no product. The chart reads each one by name
  # through a `secretKeyRef` and maps it onto whichever environment variable this particular
  # server expects, so the Secret's schema is this module's and stays put across a change of
  # implementation. A Secret whose keys are the current server's variable names is a Secret that
  # has to be rewritten when the server changes — which is exactly the coupling a `secretKeyRef`
  # exists to avoid, and which only appears when a chart consumes the whole Secret through
  # `envFrom` instead.
  access_key_key = "ACCESS_KEY"
  secret_key_key = "SECRET_KEY"
  secret_keys    = [local.access_key_key, local.secret_key_key]

  # A name was given, or this module renders one. Both branches produce a name; only one produces
  # an object.
  render_secret = var.secret_name == null
  secret_name   = coalesce(var.secret_name, "object-storage-credentials")

  # The Service the chart renders, which is what every consumer is configured with. Fully
  # qualified because consumers live in other namespaces, and on the API's port because that is
  # the only one anything in this platform talks to.
  endpoint = "${local.service}.${var.namespace}.svc.cluster.local:${var.services.api.port}"

  api_url     = var.services.api.hostname == null ? null : "https://${var.services.api.hostname}"
  console_url = var.services.management_console.hostname == null ? null : "https://${var.services.management_console.hostname}"

  # **What each routed surface is told its own external address is, and the two must not be the
  # same string.** A server behind a route has no way to learn the hostname a request arrived on
  # before proxying, so it advertises whatever it was configured with: the API signs URLs against
  # its address and the console redirects back to its own after a login. Configured with one
  # address for both, the console's redirect lands on the API and the API's signed URLs point at
  # the console — the request is well-formed and the signature does not match, which reads as a
  # credential problem rather than a routing one. The chart refuses to render the two equal, and
  # `services` refuses to accept them equal, so this map cannot produce them.
  #
  # A surface that is not routed contributes no key at all rather than an empty string: the value
  # is absent, and the process falls back to advertising its in-cluster address, which is the
  # correct answer for something nothing outside can reach anyway.
  external_url = merge(
    local.api_url == null ? {} : { api = local.api_url },
    local.console_url == null ? {} : { console = local.console_url },
  )

  # One route per exposed surface, each on its own hostname, its own Gateway and its own listener.
  # A surface with no hostname produces no key here and therefore no route at all — that, and
  # nothing else, is what "not exposed" means. An empty hostname would be the other reading and is
  # worse than useless: a hostname-less HTTPRoute matches *every* host arriving at that listener,
  # so a surface nobody meant to expose would catch traffic aimed at everything else on a shared
  # Gateway.
  #
  # The chart renders these itself, from this value, and the Application owns them. Nothing here
  # writes a manifest and OpenTofu creates no Kubernetes object.
  #
  # `sectionName` is omitted rather than sent as null when no listener was named, which attaches
  # the route to every listener on the Gateway — right when a Gateway terminates one protocol on
  # one port, and the reason it can be left out at all.
  routable = {
    api     = var.services.api
    console = var.services.management_console
  }

  routes = {
    for surface, s in local.routable : surface => {
      hostname = s.hostname
      gateway = merge(
        {
          name      = s.gateway.name
          namespace = s.gateway.namespace
        },
        s.gateway.section_name == null ? {} : { sectionName = s.gateway.section_name },
      )
    } if s.hostname != null
  }

  # The values this repository's own chart takes. Every key here is that chart's published
  # interface rather than an upstream vendor's, so the two move together in one commit — but they
  # are still two artifacts, and a key spelled wrong is a value silently ignored rather than an
  # error, in Helm as everywhere.
  #
  # `region` is sent even though a single-node store has no region to be in: every S3 client signs
  # its requests with one, and a signature computed against a different region than the server
  # expects fails as an authorization error rather than as a mismatch anybody can see.
  #
  # `tuning` and `resources` arrive together on purpose — the numbers in the first are only
  # correct relative to the second, and the chart refuses to render a memory limit without the
  # runtime ceiling that keeps the process inside it.
  silo_values = yamlencode(merge(
    {
      fullnameOverride = local.service

      image = {
        tag = var.silo.image_tag
      }

      # One number per surface, driving the Service port, its targetPort, the containerPort and
      # what the process binds. They are one value in this chart precisely so they cannot disagree.
      service = {
        apiPort     = var.services.api.port
        consolePort = var.services.management_console.port
      }

      region = var.region

      # By reference, never by value. This module holds the Secret's name and the name of each key
      # inside it, and never the access key itself — so nothing sensitive reaches this values
      # document, the rendered Application spec, or state.
      credentials = {
        existingSecret = {
          name         = local.secret_name
          accessKeyKey = local.access_key_key
          secretKeyKey = local.secret_key_key
        }
      }

      externalUrl = local.external_url

      persistence = {
        size         = var.storage.size
        storageClass = var.storage.class
      }

      routes = local.routes

      # Counts on this side, text on the chart's: every one of these leaves the pod as an
      # environment variable, so the conversion happens here rather than in a template where a
      # bare number would render unquoted and reach the API server as the wrong type.
      tuning = {
        goMemLimit     = var.resources.go_memory_limit
        goMaxProcs     = tostring(var.resources.go_max_procs)
        apiRequestsMax = tostring(var.resources.api_requests_max)
      }

      resources = {
        requests = {
          cpu    = var.resources.requests.cpu
          memory = var.resources.requests.memory
        }
        limits = {
          cpu    = var.resources.limits.cpu
          memory = var.resources.limits.memory
        }
      }
    },
    # Each of the three is omitted entirely when unset rather than rendered empty. An empty
    # `affinity: {}` or `tolerations: []` in a values file is not the same as an absent one to
    # every chart that guards on truthiness, and a pod spec carrying an empty affinity block is a
    # constraint the API server has to be asked about for no reason.
    local.placement,
  ))

  placement = merge(
    var.placement.node_selector == null ? {} : { nodeSelector = var.placement.node_selector },
    var.placement.affinity == null ? {} : { affinity = var.placement.affinity },
    var.placement.tolerations == null ? {} : { tolerations = var.placement.tolerations },
  )

  # One static entry per chart, as a List generator requires even at one. The Secret's element
  # comes from the shared module and is an empty list when this module was given a name — there is
  # then nothing to render and nothing to own.
  #
  # Both elements read from git now, because both charts are this repository's. Each still carries
  # the `chart` key the Application template branches on, empty, because a List generator's
  # elements must agree on their keys and the template evaluates neither branch it did not select.
  #
  # The waves are load-bearing: the workload refuses to start without an access key, so the Secret
  # has to exist before it syncs. Empty is enough for the pod to be scheduled.
  charts = concat(
    module.credentials[*].element,
    [{
      name        = local.release
      source_kind = "git"
      repo_url    = var.git_repository.url
      chart       = ""
      path        = local.chart_path
      revision    = var.git_repository.revision
      namespace   = var.namespace
      wave        = "1"
      values      = local.silo_values
    }],
  )
}
