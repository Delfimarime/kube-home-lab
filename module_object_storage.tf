module "object_storage" {
  source = "./modules/object-storage-silo"
  argocd = {
    namespace = var.argocd.namespace
  }
  namespace      = var.object_storage.namespace
  secret_name    = var.object_storage.secret_name
  region         = var.object_storage.region
  storage        = var.object_storage.storage
  placement      = var.object_storage.placement
  resources      = var.object_storage.resources
  silo           = { image_tag = var.object_storage.image_tag }
  git_repository = var.git_repository
  services = {
    api                = local.object_storage_services.api
    management_console = local.object_storage_services.management_console
  }
}
