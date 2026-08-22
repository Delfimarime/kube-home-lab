module "identity" {
  source = "./modules/openid-connect-keycloak"
  count  = var.identity == null ? 0 : 1
  argocd = {
    namespace = var.argocd.namespace
  }
  namespace                   = var.identity.namespace
  database                    = var.identity.database
  gateway                     = local.identity_gateway
  bootstrap_admin_secret_name = var.identity.bootstrap_admin_secret_name
  metrics                     = local.metrics.identity
  keycloak = {
    version = var.identity.version
    image   = var.identity.image
  }
  git_repository = var.git_repository
}
