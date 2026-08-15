# The lab's certificate authorities and its trust bundle.
#
# Two authorities, not one. A single root would let the wildcard server certificate authenticate
# as a client, and whether that is caught would depend on the Gateway checking Extended Key
# Usage. Splitting them makes it structural (CERT-05).
#
# The module's own default names `*.lab.internal` directly, which is a convenience for driving it
# in isolation. Composing from `var.domain` here is what makes the certificate follow the cluster
# rather than a constant that happens to match it.
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
        # Short: cert-manager renews at two thirds of lifetime by default, which would leave the
        # expiry metric describing a certificate nobody has deployed.
        renew_before = "720h"
      }
    }
  }

  gateway_namespace = var.gateway_namespace
  metrics           = var.metrics
}
