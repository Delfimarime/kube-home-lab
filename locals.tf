locals {
  object_storage_services = {
    for name, s in var.object_storage.services : name => {
      port     = s.port
      hostname = s.hostname
      gateway = s.hostname == null ? null : {
        name         = s.gateway.name != null ? s.gateway.name : var.gateway.name
        namespace    = s.gateway.namespace != null ? s.gateway.namespace : var.gateway.namespace
        section_name = s.gateway.section_name != null ? s.gateway.section_name : var.gateway.section_name
      }
    }
  }
  observability = var.observability

  # The fact every module with a /metrics endpoint needs before it may declare scraping, derived
  # rather than declared: the operator's CRDs and the collector that reads them ship with the
  # metrics store and with nothing else, so shipping one is what makes scraping possible. A flag
  # beside it could say otherwise, and the sync it breaks would be somewhere else entirely.
  #
  # An environment whose CRDs come from outside this repo cannot say so, and that is deliberate —
  # there would be no way to check it, and the check is the point.
  metrics_enabled = !var.initial_deployment && try(local.observability.components.metrics, null) != null

  # The tenant a unit's own telemetry is stored under: its own where it states one, this cluster's
  # own otherwise. Null while no metrics store exists, because a tenant is a partition of a store
  # and there is nothing yet to partition — the label would then be written for a collector that is
  # not running.
  #
  # Every unit here is platform infrastructure and belongs to the cluster's tenant by default. The
  # per-unit field exists for the environment that splits them, and each unit's is validated against
  # the tenant map where it is written.
  metrics = {
    cert_manager = {
      enabled = local.metrics_enabled
      tenant  = local.metrics_enabled ? coalesce(var.cert_manager.tenant, local.observability.default_tenant) : null
    }
    console = {
      enabled = local.metrics_enabled
      tenant  = local.metrics_enabled ? coalesce(try(local.observability.console.tenant, null), local.observability.default_tenant) : null
    }
    identity = {
      enabled = local.metrics_enabled
      tenant  = local.metrics_enabled ? coalesce(try(var.identity.tenant, null), local.observability.default_tenant) : null
    }
    resource_authorization = {
      enabled = local.metrics_enabled
      tenant  = local.metrics_enabled ? coalesce(try(var.resource_authorization.tenant, null), local.observability.default_tenant) : null
    }
  }


  # The issuer's Gateway, resolved the same way every other exposed surface here is: it names its
  # own host and inherits the rest of the listener from the cluster's Gateway, so an environment
  # states that once.
  #
  # Unlike the others there is no null branch. An issuer with no address publishes no issuer_url,
  # which the module refuses — so an environment that ships this module has already stated a
  # hostname, and this expression has nothing to guard.
  identity_gateway = var.identity == null ? null : {
    name         = coalesce(var.identity.gateway.name, var.gateway.name)
    namespace    = coalesce(var.identity.gateway.namespace, var.gateway.namespace)
    hostname     = var.identity.hostname
    section_name = var.identity.gateway.section_name != null ? var.identity.gateway.section_name : var.gateway.section_name
  }

  # Each store's version pin is written beside the signal it pins, and the storage module takes it
  # one variable per chart. Dropped here rather than widened there: what a store is configured as
  # and which build of it runs are two different questions, and only the first is per-signal.
  observability_components = local.observability == null ? null : {
    for signal, c in local.observability.components : signal => c == null ? null : {
      bucket         = c.bucket
      retention      = c.retention
      object_storage = c.object_storage
    }
  }

  # Unset, the stores read the object store this cluster already runs, and the address comes from
  # the module that owns it rather than being written down twice. The credential deliberately does
  # not: a Secret is namespaced, so the copy sitting beside the object store is unreadable from
  # the observability namespace and the stores get a placeholder of their own to fill in. Two
  # copies of one value, and nothing here checks they agree — the symptom of getting it wrong is
  # every write returning 403 while all three stores look healthy.
  observability_object_storage = local.observability == null ? null : (
    local.observability.object_storage != null ? local.observability.object_storage : {
      endpoint       = module.object_storage.endpoint
      region         = module.object_storage.region
      secret_name    = null
      access_key_key = "RUSTFS_ACCESS_KEY"
      secret_key_key = "RUSTFS_SECRET_KEY"
      insecure       = true
    }
  )

  # Each exposed surface names its own host and inherits the rest of the Gateway from the cluster's
  # own, so an environment states the listener once. A surface with no hostname is not routed at
  # all, and passing a Gateway for it would be describing a route nothing renders.
  observability_expose_gateway = try(local.observability.expose.hostname, null) == null ? null : {
    name         = coalesce(local.observability.expose.gateway.name, var.gateway.name)
    namespace    = coalesce(local.observability.expose.gateway.namespace, var.gateway.namespace)
    hostname     = local.observability.expose.hostname
    section_name = local.observability.expose.gateway.section_name != null ? local.observability.expose.gateway.section_name : var.gateway.section_name
  }

  observability_console_gateway = try(local.observability.console.hostname, null) == null ? null : {
    name         = coalesce(local.observability.console.gateway.name, var.gateway.name)
    namespace    = coalesce(local.observability.console.gateway.namespace, var.gateway.namespace)
    hostname     = local.observability.console.hostname
    section_name = local.observability.console.gateway.section_name != null ? local.observability.console.gateway.section_name : var.gateway.section_name
  }
}
