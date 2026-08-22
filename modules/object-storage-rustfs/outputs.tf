# Three values, and none of them names the product. A consumer wired to these is configured for
# S3 and would not notice the implementation changing underneath it.
#
# Nothing here is sensitive: an address, a region, and the name of a Secret. The access key itself
# never passes through this module.

output "endpoint" {
  value       = local.endpoint
  description = "Host and port of the S3 API, in-cluster. No scheme: every S3 client takes the host separately from whether it speaks TLS, and in-cluster it does not."
}

output "region" {
  value       = var.region
  description = "The region every client must send. Arbitrary, and it has to match on both sides."
}

output "api_url" {
  value       = local.api_url
  description = "The S3 API from outside the cluster. null unless it was given a hostname — and what may reach it is the listener's business, not this module's."
}

output "console_url" {
  value       = local.console_url
  description = "The management console from outside the cluster. null unless it was given a hostname, which is the right setting unless somebody has a reason."
}

output "credentials_secret_name" {
  value       = local.secret_name
  description = "The Secret holding the access key pair — the name given, or the one this module rendered. Published in both cases so what to fill in is discoverable without knowing which."
}
