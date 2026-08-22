# An address and three Secret names. Nothing here is sensitive: no credential value passes through
# this module at all, in either mode.
#
# **Every name is published in both modes**, so what remains to be filled in is discoverable by
# reading an output rather than by working out which mode the caller chose — and a caller that
# resolved a name from a fallback does not hold the same expression twice.

output "console_url" {
  value       = local.console_url
  description = "The console from outside the cluster, and the redirect URI its OIDC client must be registered with. null unless it was given a gateway — and what may reach it is the listener's business, not this module's."
}

output "database_secret_name" {
  value       = local.database_secret_name
  description = "The Secret holding the database credential — the name given, or the one this module rendered."
}

output "admin_secret_name" {
  value       = local.admin_secret_name
  description = "The Secret holding Grafana's administrator account — the name given, or the one this module rendered. Empty until somebody fills it, and that account is the only way in when the issuer is unreachable."
}

output "oidc_secret_name" {
  value       = local.oidc_secret_name
  description = "The Secret holding the OIDC client secret — the name given, or the one this module rendered. null when no issuer is wired, because there is then no client to hold a secret for."
}
