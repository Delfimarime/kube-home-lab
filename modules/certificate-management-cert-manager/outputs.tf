# Every output names a plain Kubernetes object — a Secret or a ConfigMap. No Issuer name, no
# ClusterIssuer kind, no CRD reference, so a consumer never has to know this capability is
# implemented by cert-manager. That is only possible because no in-cluster workload requests a
# certificate; the day one does, it will need an issuer reference and this property ends.
#
# Nothing is sensitive and nothing is marked so: a private key never leaves the Secret
# cert-manager owns, so there is none here to protect.

output "ca_secret_names" {
  value       = local.ca_secret_names
  description = "The two authorities, server and client, each mapped to the Secret holding its own certificate. A listener's frontendValidation reads the client one."
}

output "certificate_secret_names" {
  value       = local.certificate_secret_names
  description = "Certificate name → the Secret holding its server certificate. A listener's certificateRefs reads one of these; `default` is the wildcard."
}

output "client_certificate_secret_names" {
  value       = local.client_certificate_secret_names
  description = "Certificate name → the Secret holding its client certificate. Only entries with mode = \"mtls\" appear."
}

output "trust_bundle_name" {
  value       = var.trust_bundle.name
  description = "The ConfigMap present in every namespace; consumers mount it."
}
