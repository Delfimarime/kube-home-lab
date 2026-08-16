# The lab's certificate authorities, its certificates and its trust bundle.
#
# A pass-through: everything cert-manager-specific is grouped under `var.cert_manager`, and the
# two values that belong to the cluster rather than to this module — where Argo CD is, and which
# namespace holds the Gateway — come from their own root variables.
#
# `gateway_namespace` rather than the whole `gateway` object, because this module emits no route:
# taking the shape to read one field would force a caller to invent a hostname nothing reads.
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
  cert_pki            = merge(var.cert_manager.cert_pki, { revision = var.git_revision })
}
