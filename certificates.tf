module "certificates" {
  source = "./modules/certificate-management-cert-manager/tofu"
  argocd = {
    namespace = var.argocd.namespace
  }
  certificate_authorities = {
    server = {
      common_name = "${var.domain} server CA"
      certificate = {
        dns_names = ["*.${var.domain}"]
        usages    = ["server auth"]
      }
    }
    client = {
      common_name = "${var.domain} client CA"
      certificate = {
        common_name = "${var.domain} client"
        usages      = ["client auth"]
        renew_before = "720h"
      }
    }
  }
  gateway_namespace = var.gateway_namespace
  metrics           = var.metrics
}
