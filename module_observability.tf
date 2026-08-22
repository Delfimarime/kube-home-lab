module "observability_storage" {
  source = "./modules/observability-storage-grafana-lgtm"
  argocd = {
    namespace = var.argocd.namespace
  }
  namespace      = local.observability.namespace
  cluster_name   = local.observability.cluster_name
  object_storage = local.observability_object_storage
  components     = local.observability_components
  retention      = local.observability.retention
  tenants        = local.observability.tenants
  default_tenant = local.observability.default_tenant
  gateway        = local.observability_expose_gateway
  # Each store's version, passed straight through — null included. An unset pin arrives as null
  # and the module's own default takes over, which is where every version here is written; these
  # three exist so one cluster can run something else without the module changing for all of them.
  # `try` is for the component being absent entirely, not for the pin being unset.
  mimir          = { image_tag = try(local.observability.components.metrics.image_tag, null) }
  loki           = { chart_version = try(local.observability.components.logs.chart_version, null) }
  tempo          = { chart_version = try(local.observability.components.traces.chart_version, null) }
  git_repository = var.git_repository
}

module "observability_console" {
  source = "./modules/observability-console-grafana"
  count  = local.observability == null || try(local.observability.console, null) == null ? 0 : 1
  argocd = {
    namespace = var.argocd.namespace
  }
  namespace   = local.observability.namespace
  metrics_url = one(module.observability_storage[*].metrics_url)
  logs_url    = one(module.observability_storage[*].logs_url)
  traces_url  = one(module.observability_storage[*].traces_url)
  database    = local.observability.console.database
  admin       = local.observability.console.admin
  oidc        = local.observability.console.oidc
  gateway     = local.observability_console_gateway
  metrics     = local.metrics.console
  # The environment's tenants, plus the two the storage module writes on its own account — its
  # workloads' own telemetry and the one a write with no header lands in. They are read from that
  # module rather than restated here: a tenant with no datasource is data nobody can look at, and
  # `unattributed` filling up is only a signal if somebody can see it.
  tenants           = concat(keys(local.observability.tenants), one(module.observability_storage[*].reserved_tenants))
  default_tenant    = local.observability.default_tenant
  trust_bundle_name = module.cert_manager.trust_bundle_name
  grafana           = { chart_version = local.observability.console.chart_version }
  git_repository    = var.git_repository
}
