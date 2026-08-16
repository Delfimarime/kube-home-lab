module "object_storage" {
  source = "./modules/object-storage-rustfs"
  argocd = {
    namespace = var.argocd.namespace
  }
  namespace      = var.object_storage.namespace
  secret_name    = var.object_storage.secret_name
  region         = var.object_storage.region
  storage        = var.object_storage.storage
  rustfs         = { chart_version = var.object_storage.chart_version }
  git_repository = var.git_repository
  services = {
    api                = local.object_storage_services.api
    management_console = local.object_storage_services.management_console
  }
}
