# What an operator needs to wire the Gateway's listeners by hand, since this repo does not
# configure them (ADR 014). Nothing here is sensitive and nothing is marked so, because a
# certificate's private key never leaves the Secret cert-manager owns (CERT-07).
#
# Modules that consume these later will reference `module.certificates.*` directly rather than
# reading them from here — that is the whole point of one root module (ADR 020).

output "ca_secret_names" {
  value       = module.certificates.ca_secret_names
  description = "Authority → Secret holding that authority's own certificate. The Gateway's frontendValidation reads the client one."
}

output "certificate_secret_names" {
  value       = module.certificates.certificate_secret_names
  description = "Authority → Secret holding the certificate it issued. The Gateway's certificateRefs reads the server one."
}

output "trust_bundle_name" {
  value       = module.certificates.trust_bundle_name
  description = "The ConfigMap present in every namespace; consumers mount it."
}
