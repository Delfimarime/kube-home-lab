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

# One console over whatever the stores above are collecting. It is separately optional because its
# hard dependency is not: Grafana does not start without a PostgreSQL, and an environment can
# usefully ingest telemetry for a while before it has one.
module "observability_console" {
  source = "./modules/observability-console-grafana"
  count  = local.observability == null || try(local.observability.console, null) == null ? 0 : 1

  argocd = {
    namespace = var.argocd.namespace
  }
  namespace = local.observability.namespace

  # Addresses rather than a copy of which components are shipped. A boolean and the store it
  # claims to describe are two truths that could disagree, and every correlation link in the
  # console derives from these — a link wired against a datasource that is not there is a link
  # that quietly returns nothing.
  metrics_url = one(module.observability_storage[*].metrics_url)
  logs_url    = one(module.observability_storage[*].logs_url)
  traces_url  = one(module.observability_storage[*].traces_url)

  database = local.observability.console.database
  admin    = local.observability.console.admin
  oidc     = local.observability.console.oidc

  gateway = local.observability_console_gateway
  metrics = local.metrics

  tenants        = keys(local.observability.tenants)
  default_tenant = local.observability.default_tenant

  # Every server-to-server call to the issuer is made against a certificate signed by an authority
  # no container trusts by default. Without this the callback fails with an unknown-authority
  # error, which reads as a broken sign-in configuration and is not one.
  trust_bundle_name = module.cert_manager.trust_bundle_name

  grafana        = { chart_version = local.observability.console.chart_version }
  git_repository = var.git_repository
}
