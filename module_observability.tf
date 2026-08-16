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
  mimir          = try(local.observability.components.metrics.image_tag, null) == null ? {} : { image_tag = local.observability.components.metrics.image_tag }
  loki           = try(local.observability.components.logs.chart_version, null) == null ? {} : { chart_version = local.observability.components.logs.chart_version }
  tempo          = try(local.observability.components.traces.chart_version, null) == null ? {} : { chart_version = local.observability.components.traces.chart_version }
  git_repository = var.git_repository
}

module "observability_console" {
  source = "./modules/observability-console-grafana"
  count  = local.observability == null || try(local.observability.console, null) == null ? 0 : 1
  argocd = {
    namespace = var.argocd.namespace
  }
  namespace         = local.observability.namespace
  metrics_url       = one(module.observability_storage[*].metrics_url)
  logs_url          = one(module.observability_storage[*].logs_url)
  traces_url        = one(module.observability_storage[*].traces_url)
  database          = local.observability.console.database
  admin             = local.observability.console.admin
  oidc              = local.observability.console.oidc
  gateway           = local.observability_console_gateway
  metrics           = local.metrics.console
  tenants           = keys(local.observability.tenants)
  default_tenant    = local.observability.default_tenant
  trust_bundle_name = module.cert_manager.trust_bundle_name
  grafana           = { chart_version = local.observability.console.chart_version }
  git_repository    = var.git_repository
}
