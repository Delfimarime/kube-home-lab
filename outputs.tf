output "ca_secret_names" {
  value       = module.cert_manager.ca_secret_names
  description = "server/client → the Secret holding that authority's own certificate. A listener's frontendValidation reads the client one."
}

output "certificate_secret_names" {
  value       = module.cert_manager.certificate_secret_names
  description = "Certificate name → the Secret holding its server certificate. A listener's certificateRefs reads one of these; `default` is the wildcard."
}

output "client_certificate_secret_names" {
  value       = module.cert_manager.client_certificate_secret_names
  description = "Certificate name → the Secret holding its client certificate. Only mtls entries appear."
}

output "trust_bundle_name" {
  value       = module.cert_manager.trust_bundle_name
  description = "The ConfigMap present in every namespace; consumers mount it."
}

# Null where the environment ships no issuer. It is here because every client is registered by
# hand in Keycloak's console, and this is the address whoever does that has to work against.
output "issuer_url" {
  value       = one(module.identity[*].issuer_url)
  description = "The OIDC issuer. A consumer's oidc.issuer_url is wired from this, and a client is registered against it by hand."
}
