locals {
  # Where this module's own charts sit inside this repository. Constants rather than inputs: the
  # only correct value is this one, and a caller able to change it could only ever point an
  # Application at a path that does not exist.
  chart_path_metrics_store = "modules/observability-storage-grafana-lgtm/helm/mimir-monolithic"
  chart_path_collector     = "modules/observability-storage-grafana-lgtm/helm/k8s-monitoring-routed"

  # Each Application's name is also its Helm release name, so the objects a chart renders are named
  # after the thing an operator is looking for. That is what makes `rollout restart statefulset/loki`
  # the obvious command rather than one that has to be looked up.
  metrics_store_release = "mimir"
  logs_store_release    = "loki"
  traces_store_release  = "tempo"
  collector_release     = "k8s-monitoring"

  # The receiver's Service names the protocol rather than the product. Its value is what workloads
  # are configured with and then never change, so it must not read as the name of whichever agent
  # happens to be terminating OTLP this year.
  receiver_service = "otlp"

  # In-cluster addresses. Each store's Service is named for its release, so these follow the names
  # above by construction; change one and change the other, or this module publishes an address
  # nothing answers on.
  metrics_store_host  = "${local.metrics_store_release}.${var.namespace}.svc.cluster.local:8080"
  logs_store_host     = "${local.logs_store_release}.${var.namespace}.svc.cluster.local:3100"
  traces_store_host   = "${local.traces_store_release}.${var.namespace}.svc.cluster.local:3200"
  traces_store_ingest = "${local.traces_store_release}.${var.namespace}.svc.cluster.local:4318"
  receiver_host       = "${local.receiver_service}.${var.namespace}.svc.cluster.local"

  # An address per store this module actually runs, and null for one it does not. The console
  # builds a datasource from each and derives which correlations it can offer from which of them is
  # non-null — which is why these are addresses rather than three booleans: "metrics are collected"
  # and "there is something to point at" cannot disagree when one value carries both.
  metrics_url = contains(keys(local.shipped), "metrics") ? "http://${local.metrics_store_host}/prometheus" : null
  logs_url    = contains(keys(local.shipped), "logs") ? "http://${local.logs_store_host}" : null
  traces_url  = contains(keys(local.shipped), "traces") ? "http://${local.traces_store_host}" : null

  # 4317 in-cluster, where OTLP/gRPC costs nothing to reach. The routed address is 4318 instead:
  # routing gRPC would need an h2c backend protocol on the Service and a GRPCRoute rather than an
  # HTTPRoute, which is two implementation-specific behaviours to depend on for a transport
  # advantage that means nothing to a laptop pushing spans over a home network.
  otlp_endpoint = "${local.receiver_host}:4317"
  otlp_url      = var.gateway == null ? null : "https://${var.gateway.hostname}"

  # The service graph spans two signals, so it needs both. With no metrics store the generator stays
  # disabled rather than remote-writing into one that is not running — which also stops the console
  # offering a Service Graph tab whose query nothing can answer.
  service_graph_enabled = contains(keys(local.shipped), "metrics") && contains(keys(local.shipped), "traces")

  # Every store reads its access key from the environment and expands it into its configuration at
  # start-up, so the credential is a Secret reference in a pod spec and never a value in a rendered
  # Application. The two names below are this module's, not any Secret's: the Secret's keys are the
  # caller's to choose, and mapping them to fixed names here is what keeps a chosen key name out of
  # three different configuration dialects — and lets three stores reading three different Secrets
  # all be configured the same way.
  access_key_env = "OBJECT_STORAGE_ACCESS_KEY"
  secret_key_env = "OBJECT_STORAGE_SECRET_KEY"

  # The literal text each store's configuration carries. Expanded by the store itself at start-up,
  # which is why every one of them is started with environment expansion switched on.
  access_key_ref = "$${${local.access_key_env}}"
  secret_key_ref = "$${${local.secret_key_env}}"
}

# ---------------------------------------------------------------------------------------------
# One signal, one block: which stores are shipped, and where each of them writes.
# ---------------------------------------------------------------------------------------------

locals {
  # A signal is collected because its block is there. There is no flag beside it that could say
  # otherwise, which is the whole reason this map is the only thing anything downstream consults.
  shipped = {
    for signal, c in {
      metrics = var.components.metrics
      logs    = var.components.logs
      traces  = var.components.traces
    } : signal => c if c != null
  }

  # Read everywhere a signal's presence decides something. Named rather than repeated so that what
  # follows says *why* a store, a collector or a route exists, and only this line says how that is
  # discovered.
  collect_metrics = contains(keys(local.shipped), "metrics")
  collect_logs    = contains(keys(local.shipped), "logs")
  collect_traces  = contains(keys(local.shipped), "traces")

  # **The override replaces; it never merges.** Every field of a store's storage comes from exactly
  # one of the two blocks, and which one is decided once, here, by whether the component carried a
  # block at all. Reaching into the top-level block for a field an override happened not to mention
  # is the bug this shape exists to make unwritable: it would point a store at somebody else's
  # endpoint while handing it this cluster's access key, which plans clean and is refused forever.
  #
  # `rendered_name` is the name this module would use if it has to create the Secret itself. Two
  # stores left on the top-level block share one name and therefore one Secret; a store carrying its
  # own block gets one prefixed by its signal.
  #
  # **Every one of them is prefixed with this module's namespace, and that is not decoration.** The
  # Secret name is also the name of the Argo CD Application rendering it, and Applications all live
  # in one namespace while Secrets live in theirs — so a plain `object-storage-credentials` here is
  # the same Application as the one `object-storage-rustfs` renders for its own copy of the same
  # credential, and the second ApplicationSet to reach it is refused with `already owned by another
  # ApplicationSet controller`. Two namespaced Secrets, two distinctly named Applications.
  storage = {
    for signal, c in local.shipped : signal => (
      c.object_storage != null ? {
        endpoint       = c.object_storage.endpoint
        region         = c.object_storage.region
        insecure       = c.object_storage.insecure
        access_key_key = c.object_storage.access_key_key
        secret_key_key = c.object_storage.secret_key_key
        given_name     = c.object_storage.secret_name
        rendered_name  = "${var.namespace}-${signal}-object-storage-credentials"
        } : {
        endpoint       = var.object_storage.endpoint
        region         = var.object_storage.region
        insecure       = var.object_storage.insecure
        access_key_key = var.object_storage.access_key_key
        secret_key_key = var.object_storage.secret_key_key
        given_name     = var.object_storage.secret_name
        rendered_name  = "${var.namespace}-object-storage-credentials"
      }
    )
  }

  # The Secret each store actually reads: the one it was given, or the one this module renders for
  # it. Either way a name and a key, and never a value.
  storage_secret_name = {
    for signal, s in local.storage : signal => coalesce(s.given_name, s.rendered_name)
  }

  storage_scheme = {
    for signal, s in local.storage : signal => s.insecure ? "http" : "https"
  }

  # One Secret reference pair per store, pointing at whichever Secret that store resolved to.
  credential_env = {
    for signal, s in local.storage : signal => [
      {
        name = local.access_key_env
        valueFrom = {
          secretKeyRef = {
            name = local.storage_secret_name[signal]
            key  = s.access_key_key
          }
        }
      },
      {
        name = local.secret_key_env
        valueFrom = {
          secretKeyRef = {
            name = local.storage_secret_name[signal]
            key  = s.secret_key_key
          }
        }
      },
    ]
  }

  # A placeholder per *distinct* Secret this module was asked to create. Two stores left on the
  # top-level block resolve to one name and must not produce two Applications of it, so the names
  # are grouped rather than collected — a duplicate key is the difference between one Secret and a
  # plan that will not build.
  #
  # A block naming an existing Secret contributes nothing: this module then only reads it, and
  # never adopts an object it did not create. If every block names one, wave 0 is empty.
  rendered_secrets = {
    for name, group in {
      for signal, s in local.storage : s.rendered_name => s... if s.given_name == null
    } : name => [group[0].access_key_key, group[0].secret_key_key]
  }
}

# ---------------------------------------------------------------------------------------------
# Retention, resolved through the levels each store already has.
# ---------------------------------------------------------------------------------------------

locals {
  # A component's own number, or the one written once for all of them. This is what lands in each
  # store's own retention limit, and therefore what a tenant nobody bounded is kept for — the gap
  # that used to sit underneath the tenant map is now a number somebody chose.
  component_retention = {
    for signal, c in local.shipped : signal => coalesce(c.retention, var.retention.default)
  }
}

# ---------------------------------------------------------------------------------------------
# Per-tenant limits, one shape in and three dialects out.
# ---------------------------------------------------------------------------------------------

locals {
  # A limit left unset is dropped rather than sent as null: a store reading null for a rate does
  # not read it as "no opinion", it reads it as zero, and zero is a limit that rejects everything.
  metrics_tenant_limits = {
    for name, t in var.tenants : name => {
      for k, v in {
        ingestion_rate       = t.metrics.limits.ingestion_rate
        ingestion_burst_size = t.metrics.limits.ingestion_burst_size
        max_series           = t.metrics.limits.max_series
        retention            = t.metrics.limits.retention
      } : k => v if v != null
    }
  }

  logs_tenant_limits = {
    for name, t in var.tenants : name => {
      for k, v in {
        ingestion_rate_mb       = t.logs.limits.ingestion_rate_mb
        ingestion_burst_size_mb = t.logs.limits.ingestion_burst_size_mb
        max_streams_per_user    = t.logs.limits.max_streams
        retention_period        = t.logs.limits.retention
      } : k => v if v != null
    }
  }

  # **The trace store's dialect is nested, and the flat spelling is not an alternative here.** Tempo
  # reads an override block twice: once as `ingestion`/`compaction`/`metrics_generator` groups, and,
  # if that fails, once as the flat legacy keys — but the legacy shape has no `defaults` key at all,
  # so a flat key written inside `defaults` fails both attempts and the process exits with
  # `failed to parse configFile /conf/tempo.yaml` before it serves anything. One dialect, the nested
  # one, in both positions.
  #
  # A group with nothing in it is left out rather than written empty, for the same reason a null
  # limit is: an empty `ingestion` block is a block, and this module states only what it was told.
  traces_tenant_limits = {
    for name, t in var.tenants : name => merge(
      t.traces.limits.ingestion_rate_bytes == null && t.traces.limits.max_traces == null ? {} : {
        ingestion = merge(
          t.traces.limits.ingestion_rate_bytes == null ? {} : { rate_limit_bytes = t.traces.limits.ingestion_rate_bytes },
          t.traces.limits.max_traces == null ? {} : { max_traces_per_user = t.traces.limits.max_traces },
        )
      },
      t.traces.limits.retention == null ? {} : {
        compaction = { block_retention = t.traces.limits.retention }
      },
    )
  }

  # The tenant a write with no header lands in. It is added here rather than being something a
  # caller can list, and it carries a short retention: it exists so a forgotten header shows up as
  # a tenant filling rather than as data the collector answered 200 to and the store then threw
  # away, and the tenant nobody meant to write to should not be the one holding data longest.
  metrics_tenants = merge(local.metrics_tenant_limits, {
    unattributed = { retention = var.retention.unattributed }
  })

  logs_tenants = merge(local.logs_tenant_limits, {
    unattributed = { retention_period = var.retention.unattributed }
  })

  # The trace store's per-tenant blocks do not inherit the defaults sitting beside them — a block
  # is read whole, so anything it omits falls back to the built-in default and not to what this
  # module configured for everybody. Every tenant therefore restates the defaults and then adds its
  # own limits on top; the other two stores merge, and only this one has to be written out.
  traces_defaults = merge(
    { compaction = { block_retention = try(local.component_retention.traces, var.retention.default) } },
    local.service_graph_enabled ? {
      metrics_generator = {
        processors = ["service-graphs", "span-metrics"]
      }
    } : {},
  )

  # Merged one group deep, which is enough because each group here holds one field from each side:
  # a tenant naming its own retention replaces a `compaction` block that carried only that.
  traces_tenants = merge(
    { for name, limits in local.traces_tenant_limits : name => merge(local.traces_defaults, limits) },
    { unattributed = merge(local.traces_defaults, { compaction = { block_retention = var.retention.unattributed } }) },
  )
}

# ---------------------------------------------------------------------------------------------
# The metrics store. One process, one pod, blocks in a bucket.
# ---------------------------------------------------------------------------------------------

locals {
  metrics_store_base = {
    image = {
      tag = var.mimir.image_tag
    }

    # Every read and write carries a tenant header. Nothing validates it — a caller states its
    # tenant and is believed — so what this buys is per-tenant limits and retention rather than
    # isolation between them.
    multitenancyEnabled = true

    # Every field comes from whichever single block this component resolved to. `try` is what makes
    # this expression evaluable when metrics are not collected at all — the values are then never
    # read by anything, because no element of the generator carries them.
    storage = {
      endpoint = try(local.storage.metrics.endpoint, "")
      region   = try(local.storage.metrics.region, "")
      bucket   = try(local.shipped.metrics.bucket, "")
      insecure = try(local.storage.metrics.insecure, true)

      # The credential by reference. The two environment variable names are what the rendered
      # configuration expands; the Secret's key names stay the caller's.
      accessKeyRef = local.access_key_ref
      secretKeyRef = local.secret_key_ref
    }

    credentialEnv = try(local.credential_env.metrics, [])

    limits = {
      retention = try(local.component_retention.metrics, var.retention.default)
    }

    tenants = local.metrics_tenants

    serviceMonitor = {
      enabled = contains(keys(local.shipped), "metrics")
    }
  }

  metrics_store_values = yamlencode({
    for k in distinct(concat(keys(local.metrics_store_base), keys(var.values.metrics))) :
    k => (
      !contains(keys(var.values.metrics), k) ? local.metrics_store_base[k] :
      !contains(keys(local.metrics_store_base), k) ? var.values.metrics[k] :
      can(merge(local.metrics_store_base[k], var.values.metrics[k])) ? merge(local.metrics_store_base[k], var.values.metrics[k]) : var.values.metrics[k]
    )
  })
}

# ---------------------------------------------------------------------------------------------
# The log store. The chart's own single-binary shape, with everything a bigger one would need
# switched off.
# ---------------------------------------------------------------------------------------------

locals {
  logs_store_base = {
    deploymentMode = "SingleBinary"

    loki = {
      # Tenancy, despite the name — it turns on the tenant header and authenticates nobody.
      auth_enabled = true

      commonConfig = {
        replication_factor = 1
      }

      # One schema, current, and stated rather than left to the chart's test schema: the store
      # writes its index in whatever version is configured on the day a block is written, and
      # discovering later that it was the placeholder one is a migration.
      schemaConfig = {
        configs = [{
          from         = "2024-04-01"
          store        = "tsdb"
          object_store = "s3"
          schema       = "v13"
          index = {
            prefix = "index_"
            period = "24h"
          }
        }]
      }

      storage = {
        type = "s3"
        # The chart wants three bucket names and this deployment has one store to point them at.
        # The third belongs to the commercial edition and is never written here.
        bucketNames = {
          chunks = try(local.shipped.logs.bucket, "")
          ruler  = try(local.shipped.logs.bucket, "")
          admin  = try(local.shipped.logs.bucket, "")
        }
        s3 = {
          endpoint         = "${try(local.storage_scheme.logs, "http")}://${try(local.storage.logs.endpoint, "")}"
          region           = try(local.storage.logs.region, "")
          accessKeyId      = local.access_key_ref
          secretAccessKey  = local.secret_key_ref
          s3ForcePathStyle = true
          insecure         = try(local.storage.logs.insecure, true)
        }
      }

      limits_config = {
        retention_period = try(local.component_retention.logs, var.retention.default)
      }

      # **Retention is declared above and enforced here.** Without `retention_enabled` the compactor
      # marks nothing for deletion and the store keeps everything forever, whatever the period says
      # — which is the failure that looks exactly like a working configuration until the bucket is
      # full. `delete_request_store` is where the compactor keeps the deletes it has decided on, and
      # it has no default that works against object storage.
      compactor = {
        retention_enabled    = true
        delete_request_store = "s3"
        working_directory    = "/var/loki/compactor"
      }

      # Per-tenant, and merged over the limits above rather than replacing them.
      runtimeConfig = {
        overrides = local.logs_tenants
      }
    }

    singleBinary = {
      replicas = 1

      # Without this the access key reference in the configuration above is written to disk
      # literally and the store authenticates with the text of its own placeholder — which the
      # object store answers with 403 while this pod stays healthy and says nothing.
      #
      # It belongs on this role and not on the chart's common one: the common setting is applied to
      # every role except this one, so putting it there renders a store that looks configured and
      # never expands anything.
      extraArgs = ["-config.expand-env=true"]

      # No volume. Everything durable is in the bucket, and the chart's default would otherwise
      # attach a claim that pins this pod to whichever node first scheduled it.
      persistence = {
        enabled = false
      }

      extraEnv = try(local.credential_env.logs, [])
    }

    # The chart carries every topology at once and decides which to render from the replica counts,
    # not from `deploymentMode` alone — with the scalable roles left at their default of three each
    # it refuses to render at all, on the grounds that one pod and nine pods together must be a
    # migration somebody is halfway through. Zeroing them is how this deployment says it is not.
    read    = { replicas = 0 }
    write   = { replicas = 0 }
    backend = { replicas = 0 }

    # The chart's defaults, and all of them pure overhead at one pod: a gateway in front of a
    # single process, two memcached deployments in front of a store nothing queries hard enough to
    # need them, and a canary writing synthetic log lines nobody reads.
    gateway      = { enabled = false }
    chunksCache  = { enabled = false }
    resultsCache = { enabled = false }
    lokiCanary   = { enabled = false }
    test         = { enabled = false }
    minio        = { enabled = false }

    # The chart ships a scrape configuration of its own, which would be a second discovery mechanism
    # beside the one the collector already uses.
    monitoring = {
      selfMonitoring = {
        enabled = false
        grafanaAgent = {
          installOperator = false
        }
      }
    }
  }

  logs_store_values = yamlencode({
    for k in distinct(concat(keys(local.logs_store_base), keys(var.values.logs))) :
    k => (
      !contains(keys(var.values.logs), k) ? local.logs_store_base[k] :
      !contains(keys(local.logs_store_base), k) ? var.values.logs[k] :
      can(merge(local.logs_store_base[k], var.values.logs[k])) ? merge(local.logs_store_base[k], var.values.logs[k]) : var.values.logs[k]
    )
  })
}

# ---------------------------------------------------------------------------------------------
# The trace store. The monolithic chart, not the distributed one.
# ---------------------------------------------------------------------------------------------

locals {
  traces_store_base = {
    replicas = 1

    tempo = {
      multitenancyEnabled = true
      reportingEnabled    = false
      retention           = try(local.component_retention.traces, var.retention.default)

      # Same reason as the log store's: the access key reaches the process as an environment
      # variable and is expanded into the configuration, never written into it.
      extraArgs = {
        "config.expand-env" = "true"
      }

      extraEnv = try(local.credential_env.traces, [])

      storage = {
        trace = {
          backend = "s3"
          s3 = {
            bucket     = try(local.shipped.traces.bucket, "")
            endpoint   = try(local.storage.traces.endpoint, "")
            region     = try(local.storage.traces.region, "")
            access_key = local.access_key_ref
            secret_key = local.secret_key_ref
            insecure   = try(local.storage.traces.insecure, true)
            # An S3-compatible endpoint in a cluster answers on one host for every bucket; the
            # virtual-hosted form would need a DNS name per bucket.
            forcepathstyle = true
          }
          wal = {
            path = "/var/tempo/wal"
          }
        }
      }

      overrides = {
        defaults                   = local.traces_defaults
        per_tenant_override_config = "/conf/overrides.yaml"
      }

      per_tenant_overrides = local.traces_tenants

      # The most expensive optional thing here: it reads every span to produce the service graph,
      # and the service graph is most of the reason this stack was chosen. It writes its series
      # into the metrics store, so it is only switched on when there is one.
      metricsGenerator = {
        enabled        = local.service_graph_enabled
        remoteWriteUrl = "http://${local.metrics_store_host}/api/v1/push"
      }
    }

    # No volume, and the chart already agrees — stated anyway, because the claim it would otherwise
    # create is the thing this design says none of the three stores owns.
    persistence = {
      enabled = false
    }

    serviceMonitor = {
      enabled = contains(keys(local.shipped), "metrics")
    }
  }

  traces_store_values = yamlencode({
    for k in distinct(concat(keys(local.traces_store_base), keys(var.values.traces))) :
    k => (
      !contains(keys(var.values.traces), k) ? local.traces_store_base[k] :
      !contains(keys(local.traces_store_base), k) ? var.values.traces[k] :
      can(merge(local.traces_store_base[k], var.values.traces[k])) ? merge(local.traces_store_base[k], var.values.traces[k]) : var.values.traces[k]
    )
  })
}

# ---------------------------------------------------------------------------------------------
# The collector, and the two destinations every signal chooses between.
# ---------------------------------------------------------------------------------------------

locals {
  # The label a workload carries to say which tenant its telemetry belongs to. It is the scrape
  # path's answer to the header a push sends: nothing discovered can be asked anything at request
  # time, so what a push states per request a scraped workload states once, in the cluster.
  #
  # **The Kubernetes label and the series label cannot share a name.** A metric label name holds
  # neither a dot nor a slash, so Kubernetes discovery exposes the sanitised form and `tenant` is
  # what the routers read. Anything writing this label to a workload writes the first spelling.
  tenant_label      = "opentelemetry.io/tenant"
  tenant_label_meta = replace(local.tenant_label, "/[^a-zA-Z0-9]+/", "_")

  # **Pod first, Service second, and the order is the whole of the precedence.** `regex = "(.+)"`
  # writes nothing when the source label is absent, so the Service's value replaces the pod's where
  # it has one and leaves it standing where it does not. Written the other way round the fallback
  # would win every time both were set.
  #
  # A PodMonitor has no Service to read, so it gets the first rule and not the second. Probes have
  # neither and are not routed at all.
  tenant_from_pod = <<-ALLOY
    rule {
      source_labels = ["__meta_kubernetes_pod_label_${local.tenant_label_meta}"]
      regex         = "(.+)"
      target_label  = "tenant"
    }
  ALLOY

  tenant_from_service = <<-ALLOY
    rule {
      source_labels = ["__meta_kubernetes_service_label_${local.tenant_label_meta}"]
      regex         = "(.+)"
      target_label  = "tenant"
    }
  ALLOY

  # One exporter per store for the pushed side, each carrying the caller's tenant forward.
  #
  # A `custom` destination is rendered verbatim, so the retry, queue and compression settings the
  # chart's own OTLP destination would have supplied are written out here, three times, and do not
  # follow a chart upgrade.
  pushed_stores = {
    metrics = {
      component = "metrics_store"
      endpoint  = "http://${local.metrics_store_host}/otlp"
    }
    logs = {
      component = "logs_store"
      endpoint  = "http://${local.logs_store_host}/otlp"
    }
    traces = {
      component = "traces_store"
      endpoint  = "http://${local.traces_store_ingest}"
    }
  }

  # **The two header blocks are one mechanism and their order is the whole of it.**
  #
  # There is no single setting meaning "use the tenant the caller sent, or this string when it sent
  # none" — a header takes a value or a source, never a source with a fallback. What reconstructs
  # it is that a metadata key which was never sent reads as the empty string rather than as an
  # error: `upsert` writes that empty header out regardless, and `insert` then treats an empty
  # header as an absent one and fills it. Written the other way round, `insert` finds nothing,
  # writes the fallback, and `upsert` immediately overwrites every real tenant with the empty
  # string — silently, and only visible as every write in the cluster landing in one place.
  #
  # **This works over HTTP and would not over gRPC**, which is why the exporter below is the HTTP
  # one and the transport is not a free choice. On the gRPC path `insert` asks whether the key is
  # present rather than whether it is empty, so it would skip the header `upsert` had just written
  # empty, and every unlabelled write would be refused by the store instead of landing somewhere it
  # can be found.
  pushed_store_config = {
    for signal, s in local.pushed_stores : signal => <<-ALLOY
      otelcol.auth.headers "${s.component}_tenant" {
        header {
          key          = "X-Scope-OrgID"
          action       = "upsert"
          from_context = "X-Scope-OrgID"
        }

        header {
          key    = "X-Scope-OrgID"
          action = "insert"
          value  = "unattributed"
        }
      }

      otelcol.exporter.otlphttp "${s.component}" {
        client {
          endpoint    = "${s.endpoint}"
          auth        = otelcol.auth.headers.${s.component}_tenant.handler
          compression = "gzip"

          tls {
            insecure = true
          }
        }

        retry_on_failure {
          enabled = true
        }

        sending_queue {
          enabled = true
        }
      }
    ALLOY
  }

  # A scraped workload states its tenant in a label ([LOCAL-008]) and this is what that label
  # becomes. **A remote-write header is fixed per endpoint**, so one header per tenant means one
  # endpoint per tenant and something in front choosing between them — there is no setting that
  # reads a tenant off a series and writes it as a header, which is why this is a set of
  # destinations rather than a field on one.
  #
  # These differ in nothing except the name they write under.
  tenant_stores = {
    metrics = { type = "prometheus", url = "http://${local.metrics_store_host}/api/v1/push" }
    logs    = { type = "loki", url = "http://${local.logs_store_host}/loki/api/v1/push" }
  }

  # `unattributed` is a destination for the same reason it is a tenant in the stores: a label naming
  # a tenant this environment does not have is a typo, and a typo that silently joined the cluster's
  # own telemetry would be indistinguishable from correct configuration. Appending it cannot collide
  # with a caller's tenant, because `var.tenants` refuses that name.
  scrape_tenants = concat(sort(keys(var.tenants)), ["unattributed"])

  # One router per label-based pipeline, built from one list of routes in two dialects.
  #
  # **The order of the routes is the behaviour.** The first match wins, so a tenant this environment
  # knows is claimed before the catch-all that follows it; and a workload carrying no label at all
  # matches nothing and lands in `defaultDestinations`, which is this cluster's own tenant — the
  # same answer it got before any of this existed.
  tenant_routers = {
    for signal, ecosystem in { metrics = "prometheus", logs = "loki" } : "${signal}-router" => {
      type      = "router"
      ecosystem = ecosystem
      routes = concat(
        [for t in sort(keys(var.tenants)) : {
          match        = [{ label = "tenant", op = "equals", value = t }]
          destinations = ["${signal}-tenant-${t}"]
        }],
        [{
          match        = [{ label = "tenant", op = "matches", value = ".+" }]
          destinations = ["${signal}-tenant-unattributed"]
        }],
      )
      defaultDestinations = ["${signal}-tenant-${var.default_tenant}"]
    }
  }

  # The scrape path and the pushed path are two different destinations for the same store, because
  # they answer the tenant question differently: a scrape carries a label a router reads, a push
  # carries a header the exporter carries forward.
  destinations = merge(
    { for t in local.scrape_tenants : "metrics-tenant-${t}" =>
      merge(local.tenant_stores.metrics, { tenantId = t }) if local.collect_metrics
    },
    local.collect_metrics ? { metrics-router = local.tenant_routers["metrics-router"] } : {},

    { for t in local.scrape_tenants : "logs-tenant-${t}" =>
      merge(local.tenant_stores.logs, { tenantId = t }) if local.collect_logs
    },
    local.collect_logs ? { logs-router = local.tenant_routers["logs-router"] } : {},

    { for k, v in {
      metrics-push = {
        type      = "custom"
        ecosystem = "otlp"
        config    = local.pushed_store_config.metrics
        metrics = {
          enabled = true
          target  = "otelcol.exporter.otlphttp.${local.pushed_stores.metrics.component}.input"
        }
      }
    } : k => v if local.collect_metrics },

    { for k, v in {
      logs-push = {
        type      = "custom"
        ecosystem = "otlp"
        config    = local.pushed_store_config.logs
        logs = {
          enabled = true
          target  = "otelcol.exporter.otlphttp.${local.pushed_stores.logs.component}.input"
        }
      }
    } : k => v if local.collect_logs },

    { for k, v in {
      traces-push = {
        type      = "custom"
        ecosystem = "otlp"
        config    = local.pushed_store_config.traces
        traces = {
          enabled = true
          target  = "otelcol.exporter.otlphttp.${local.pushed_stores.traces.component}.input"
        }
      }
    } : k => v if local.collect_traces },
  )

  pushed_destinations = compact([
    local.collect_metrics ? "metrics-push" : "",
    local.collect_logs ? "logs-push" : "",
    local.collect_traces ? "traces-push" : "",
  ])

  # Which Alloy instances exist follows the flags, and that is what keeps this proportionate on two
  # nodes. The receiver is the one that is always here: OTLP carries all three signals over one
  # listener, so gating it on any single flag would leave the published address pointing at nothing
  # on an environment that switched that one off.
  collectors = merge(
    {
      alloy-receiver = {
        # What names the Service every workload is configured with. A values line rather than a
        # second object, and the reason the published address reads as a protocol.
        fullnameOverride = local.receiver_service
        presets          = ["deployment", "otel-receiver"]
      }
    },

    local.collect_metrics ? {
      alloy-metrics = {
        presets = ["deployment"]
      }
    } : {},

    local.collect_logs ? {
      alloy-logs = {
        presets = ["daemonset", "filesystem-log-reader"]
      }
      alloy-singleton = {
        presets = ["singleton"]
      }
    } : {},
  )

  collector_base = {
    # The wrapper's own values: everything below `k8s-monitoring` belongs to the chart it depends
    # on, and nothing in that dialect is re-authored here.
    gateway = var.gateway == null ? null : {
      name        = var.gateway.name
      namespace   = var.gateway.namespace
      hostname    = var.gateway.hostname
      sectionName = var.gateway.section_name
    }

    receiver = {
      service = local.receiver_service
      port    = 4318
    }

    # One rule per switched-on signal, so pushing a signal this environment does not store gets a
    # 404 rather than being accepted and dropped. The paths are the ones the protocol itself
    # defines, which is why this is not the three hostnames that were refused: those would have
    # resolved to one socket on one pod and encoded a distinction living a layer below them.
    routes = {
      metrics = local.collect_metrics
      logs    = local.collect_logs
      traces  = local.collect_traces
    }

    "k8s-monitoring" = {
      cluster = {
        name = var.cluster_name
      }

      destinations = local.destinations
      collectors   = local.collectors

      # Cluster-wide metrics belong to no workload and therefore to no tenant: they are written as
      # this cluster's own directly, rather than through a router that has nothing to match on.
      clusterMetrics = {
        enabled      = local.collect_metrics
        collector    = "alloy-metrics"
        destinations = local.collect_metrics ? ["metrics-tenant-${var.default_tenant}"] : []
      }

      # The only discovery that reads a workload's own declaration, and therefore the only one whose
      # writes are routed.
      prometheusOperatorObjects = {
        enabled      = local.collect_metrics
        collector    = "alloy-metrics"
        destinations = local.collect_metrics ? ["metrics-router"] : []

        serviceMonitors = {
          extraDiscoveryRules = "${local.tenant_from_pod}${local.tenant_from_service}"
        }

        podMonitors = {
          extraDiscoveryRules = local.tenant_from_pod
        }
      }

      # Logs are discovered from pods and there is no Service anywhere in this pipeline, so a tenant
      # written only on a Service routes that workload's metrics and not its logs. The pod label is
      # the one that covers both.
      #
      # The chart's own pod-label-to-Loki-label mapping does what the metrics side needs two hand
      # written rules for. Its default entry is restated so the whole mapping reads in one place.
      podLogsViaLoki = {
        enabled      = local.collect_logs
        collector    = "alloy-logs"
        destinations = local.collect_logs ? ["logs-router"] : []

        labels = {
          app_kubernetes_io_name = "app.kubernetes.io/name"
          tenant                 = local.tenant_label
        }
      }

      # Events are the API server's account of the cluster, not any workload's output. Same
      # reasoning as clusterMetrics: written as this cluster's own, unrouted.
      clusterEvents = {
        enabled      = local.collect_logs
        collector    = "alloy-singleton"
        destinations = local.collect_logs ? ["logs-tenant-${var.default_tenant}"] : []
      }

      applicationObservability = {
        enabled      = true
        collector    = "alloy-receiver"
        destinations = local.pushed_destinations

        # Request metadata has to survive into the pipeline or there is no incoming tenant for the
        # exporters above to read back out.
        receivers = {
          otlp = {
            grpc = {
              enabled         = true
              port            = 4317
              includeMetadata = true
            }
            http = {
              enabled         = true
              port            = 4318
              includeMetadata = true
            }
          }
        }

        # A pipeline for a signal with no store behind it would be a destination the chart cannot
        # resolve. In-cluster the listener still accepts that signal and the data goes nowhere,
        # which is the one place this module's behaviour differs inside and outside the cluster.
        metrics = { enabled = local.collect_metrics }
        logs    = { enabled = local.collect_logs }
        traces  = { enabled = local.collect_traces }
      }

      # A second discovery mechanism beside the operator CRDs. Running both means a target can be
      # declared in two places, scraped twice, and authoritative in neither.
      annotationAutodiscovery = {
        enabled = false
      }

      # These follow the metrics flag rather than arriving as a side effect of whichever metrics
      # store was chosen, so swapping that store again leaves them where they are. Both are per-node
      # or cluster-wide exporters with nothing to send anywhere if metrics are off.
      telemetryServices = {
        kube-state-metrics = { deploy = local.collect_metrics }
        node-exporter      = { deploy = local.collect_metrics }
      }

      # It emits metrics about the collector itself, which needs a metrics destination to exist. On
      # a logs-only environment there is none, so this would be a chart failure rather than a
      # missing dashboard.
      selfReporting = {
        enabled = false
      }
    }
  }

  collector_values = yamlencode({
    for k in distinct(concat(keys(local.collector_base), keys(var.values.collector))) :
    k => (
      !contains(keys(var.values.collector), k) ? local.collector_base[k] :
      !contains(keys(local.collector_base), k) ? var.values.collector[k] :
      can(merge(local.collector_base[k], var.values.collector[k])) ? merge(local.collector_base[k], var.values.collector[k]) : var.values.collector[k]
    )
  })
}

# ---------------------------------------------------------------------------------------------
# The generator's elements.
# ---------------------------------------------------------------------------------------------

locals {
  # One static entry per chart, as a List generator requires even at one. The credential elements
  # come from the shared module — one per distinct Secret this module renders, and none at all when
  # every storage block names an existing one. Sorted by name so that adding a signal does not
  # reorder the elements of the ones already there.
  #
  # **The waves are load-bearing.** A List generator has no inherent order, so without them the
  # operator CRDs may not exist when the collector's generated configuration references the API
  # types it discovers scrape targets through, and the stores may sync before the credential they
  # authenticate with exists. The second resolves itself in a crash loop; the first does not, and
  # reads as a broken chart.
  charts = concat(
    [for name in sort(keys(module.credentials)) : module.credentials[name].element],

    local.collect_metrics ? [{
      name        = "prometheus-operator-crds"
      source_kind = "helm"
      repo_url    = "https://prometheus-community.github.io/helm-charts"
      chart       = "prometheus-operator-crds"
      path        = ""
      revision    = var.prometheus_operator_crds.chart_version
      namespace   = var.namespace
      wave        = "0"
      values      = yamlencode({})
    }] : [],

    local.collect_metrics ? [{
      name        = local.metrics_store_release
      source_kind = "git"
      repo_url    = var.git_repository.url
      chart       = ""
      path        = local.chart_path_metrics_store
      revision    = var.git_repository.revision
      namespace   = var.namespace
      wave        = "1"
      values      = local.metrics_store_values
    }] : [],

    local.collect_logs ? [{
      name        = local.logs_store_release
      source_kind = "helm"
      repo_url    = "https://grafana.github.io/helm-charts"
      chart       = "loki"
      path        = ""
      revision    = var.loki.chart_version
      namespace   = var.namespace
      wave        = "1"
      values      = local.logs_store_values
    }] : [],

    local.collect_traces ? [{
      name        = local.traces_store_release
      source_kind = "helm"
      repo_url    = "https://grafana.github.io/helm-charts"
      chart       = "tempo"
      path        = ""
      revision    = var.tempo.chart_version
      namespace   = var.namespace
      wave        = "1"
      values      = local.traces_store_values
    }] : [],

    [{
      name        = local.collector_release
      source_kind = "git"
      repo_url    = var.git_repository.url
      chart       = ""
      path        = local.chart_path_collector
      revision    = var.git_repository.revision
      namespace   = var.namespace
      wave        = "2"
      values      = local.collector_values
    }],
  )
}
