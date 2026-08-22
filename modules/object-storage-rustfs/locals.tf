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
  # qualified because consumers live in other namespaces, and on the API's port because that is
  # the only one anything in this platform talks to.
  service  = "${local.release}-svc"
  endpoint = "${local.service}.${var.namespace}.svc.cluster.local:${var.services.api.port}"

  api_url     = var.services.api.hostname == null ? null : "https://${var.services.api.hostname}"
  console_url = var.services.management_console.hostname == null ? null : "https://${var.services.management_console.hostname}"

  # The route, rendered through the chart's own `extraManifests` rather than by wrapping the
  # chart. The chart *has* Gateway API support and it cannot be used: its HTTPRoute's backend port
  # is hardcoded to the console's, it emits a second hostname-less redirect route that would catch
  # every plaintext host on a shared Gateway, and it creates a Gateway of its own whenever it is
  # not given one — which this repository never provisions.
  #
  # `extraManifests` entries are rendered through `tpl`, so this is a manifest the chart owns and
  # renders; OpenTofu still creates no Kubernetes object.
  #
  # One route per exposed surface, each on its own hostname, its own Gateway and its own listener.
  # A surface with no hostname produces no route at all — that, and nothing else, is what "not
  # exposed" means here.
  routable = {
    (local.release)            = var.services.api
    "${local.release}-console" = var.services.management_console
  }

  http_routes = [
    for name, s in local.routable : {
      apiVersion = "gateway.networking.k8s.io/v1"
      kind       = "HTTPRoute"
      metadata = {
        name      = name
        namespace = var.namespace
      }
      spec = {
        parentRefs = [merge(
          {
            name      = s.gateway.name
            namespace = s.gateway.namespace
          },
          s.gateway.section_name == null ? {} : { sectionName = s.gateway.section_name },
        )]
        hostnames = [s.hostname]
        rules = [{
          backendRefs = [{
            name = local.service
            port = s.port
          }]
        }]
      }
    } if s.hostname != null
  ]

  # standalone: one pod, one volume. The chart's default is `distributed` — four replicas across
  # sixteen volumes — so both halves are stated rather than relying on one switch to imply the
  # other.
  #
  # ingress is switched off explicitly and this is the important line: the chart defaults it to
  # *enabled*, with an nginx class, so leaving it alone would expose the store by default.
  # gatewayApi is off for the reasons above the route itself; what exposes this module is
  # `extraManifests`, and only when a gateway was given.
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

      ingress        = { enabled = false }
      gatewayApi     = { enabled = false }
      extraManifests = local.http_routes

      # Both halves of each port, together. `service.<x>.port` drives the Service port, its
      # targetPort and the containerPort; `address`/`console_address` are what the process
      # actually binds. They are separate values in this chart and must agree.
      service = {
        endpoint = { port = var.services.api.port }
        console  = { port = var.services.management_console.port }
      }

      # Nothing sets the probes' port, and nothing should: the chart renders both from
      # `service.endpoint.port`, so they follow the API's port on their own. Its values.yaml
      # *documents* `livenessProbe.httpGet.port` and `readinessProbe.httpGet.port` and reads
      # neither — two keys that look like knobs and are not.

      config = {
        rustfs = {
          region            = var.region
          address           = ":${var.services.api.port}"
          console_address   = ":${var.services.management_console.port}"
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
