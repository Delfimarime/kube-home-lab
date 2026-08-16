locals {
  # Everything the chart renders is named from this, and it names the protocol rather than the
  # product: the published address is what consumers are configured with, and swapping the
  # implementation should not be a re-configuration of every consumer. The chart appends `-svc`
  # to it for the Service, which is why the endpoint below is not simply this name.
  release = "s3"

  # The two key names are the chart's, not this module's, and they are environment variable names
  # because the workload consumes the whole Secret through `envFrom` rather than picking keys out
  # of it. A Secret carrying the right values under any other names produces a container with no
  # credential and an error that reads as a broken image.
  secret_keys = ["RUSTFS_ACCESS_KEY", "RUSTFS_SECRET_KEY"]

  # A name was given, or this module renders one. Both branches produce a name; only one produces
  # an object.
  render_secret = var.secret_name == null
  secret_name   = coalesce(var.secret_name, "object-storage-credentials")

  # The Service the chart renders, which is what every consumer is configured with. Fully
  # qualified because consumers live in other namespaces.
  endpoint = "${local.release}-svc.${var.namespace}.svc.cluster.local:9000"

  # standalone: one pod, one volume. The chart's default is `distributed` — four replicas across
  # sixteen volumes — so both halves are stated rather than relying on one switch to imply the
  # other.
  #
  # ingress is switched off explicitly and this is the important line: the chart defaults it to
  # *enabled*, with an nginx class, so leaving it alone would expose the store by default. What
  # the chart's own gatewayApi support would render is a route to the console on port 9001, plus
  # a redirect route and a Traefik-specific sticky-session object — an admin UI over every stored
  # object, which is the one thing this module must never expose. So both are off, and nothing
  # here is reachable from outside the cluster.
  #
  # obs_log_directory is blanked deliberately: a value there sends the workload's logs to a second
  # PVC instead of stdout, where nothing tails them. Blank removes the volume and makes the logs
  # readable by whatever collects containers.
  #
  # obs_endpoint stays disabled. RustFS emits its own telemetry over OTLP, and the collector that
  # would receive it stores everything in this store — so wiring it here would be a cycle, both in
  # the plan graph and in reality.
  rustfs_values = yamlencode(merge(
    {
      fullnameOverride = local.release

      mode = {
        standalone  = { enabled = true }
        distributed = { enabled = false }
      }

      secret = {
        existingSecret = local.secret_name
      }

      ingress    = { enabled = false }
      gatewayApi = { enabled = false }

      config = {
        rustfs = {
          region            = var.region
          obs_log_directory = ""
          obs_endpoint      = { enabled = false }
        }
      }

      storageclass = {
        name            = var.storage.class
        dataStorageSize = var.storage.size
      }
    },
    var.storage.node_selector == null ? {} : { nodeSelector = var.storage.node_selector },
  ))

  # One static entry per chart, as a List generator requires even at one. The Secret's element
  # comes from the shared module and is an empty list when this module was given a name — there is
  # then nothing to render and nothing to own.
  #
  # The waves are load-bearing: the workload refuses to start without an access key, so the Secret
  # has to exist before it syncs. Empty is enough for the pod to be scheduled.
  charts = concat(
    module.credentials[*].element,
    [{
      name        = "rustfs"
      source_kind = "helm"
      repo_url    = "https://charts.rustfs.com"
      chart       = "rustfs"
      path        = ""
      revision    = var.rustfs.chart_version
      namespace   = var.namespace
      wave        = "1"
      values      = local.rustfs_values
    }],
  )
}
