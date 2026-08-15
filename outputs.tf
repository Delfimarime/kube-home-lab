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
