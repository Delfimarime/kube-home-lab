# Every output names a plain Kubernetes object. No Issuer name, no ClusterIssuer kind, nothing
# cert-manager-shaped crosses this boundary — so REQ-09 costs nothing here. That only works
# because no in-cluster workload requests a certificate; the day one does, it will need an
# issuer reference and this property ends.
#
# Nothing is marked sensitive, because nothing needs to be: these are names, and the material
# they name was created by a controller and never passed through Terraform (CERT-07).

output "ca_secret_names" {
  value       = local.ca_secret_names
  description = <<-EOT
    Authority -> the Secret holding that authority's own certificate.
    The Gateway's mTLS listener reads the client one as its frontendValidation CA.
  EOT
}

output "certificate_secret_names" {
  value       = local.certificate_secret_names
  description = <<-EOT
    Authority -> the Secret holding the one certificate it signed.
    The Gateway's listeners read the server one as a certificateRef; the client one is fetched
    by hand and carried to whatever pushes telemetry.
  EOT
}

output "trust_bundle_name" {
  value       = var.trust_bundle.name
  description = <<-EOT
    The ConfigMap present in every namespace. Consumers mount it; nothing makes them, and a
    consumer that forgets fails exactly as it would have with no trust-manager at all.
  EOT
}
