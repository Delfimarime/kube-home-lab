module "cert_manager" {
  source = "./modules/certificate-management-cert-manager"
  argocd = {
    namespace = var.argocd.namespace
  }
  gateway_namespace   = var.gateway.namespace
  metrics             = var.metrics
  namespace           = var.cert_manager.namespace
  domain              = var.cert_manager.domain
  certificates        = var.cert_manager.certificates
  default_certificate = var.cert_manager.default_certificate
  authority           = var.cert_manager.authority
  trust_bundle        = var.cert_manager.trust_bundle
  cert_manager        = { chart_version = var.cert_manager.chart_version }
  trust_manager       = var.cert_manager.trust_manager
  git_repository      = var.git_repository
}
