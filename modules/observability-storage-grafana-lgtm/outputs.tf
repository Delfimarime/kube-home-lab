output "otlp_endpoint" {
  value       = local.otlp_endpoint
  description = "Host and port of the OTLP receiver, in-cluster. One listener for all three signals; the caller selects which by gRPC method. What cannot be scraped is pushed here."
}

output "otlp_url" {
  value       = local.otlp_url
  description = "The OTLP receiver from outside the cluster, over HTTP — null unless a gateway was given. What may reach it is the listener's business, not this module's."
}

output "metrics_url" {
  value       = local.metrics_url
  description = "The metrics store, in-cluster, as a datasource address. null when this environment does not collect metrics."
}

output "logs_url" {
  value       = local.logs_url
  description = "The log store, in-cluster, as a datasource address. null when this environment does not collect logs."
}

output "traces_url" {
  value       = local.traces_url
  description = "The trace store, in-cluster, as a datasource address. null when this environment does not collect traces."
}

output "object_storage_secret_names" {
  value       = local.storage_secret_name
  description = "Signal → the Secret that store reads its object store's access key from, whether named by the caller or rendered here. Published so what an operator owes is discoverable without knowing which, and keyed by signal because a store pointed at its own endpoint has a credential of its own."
}

# The tenants this module writes that no caller may list: its own workloads' telemetry, and the one
# a write with no header lands in. Published so the console can build a datasource for each — a
# tenant nothing can query is one nobody can be told about, which would leave `unattributed` filling
# up as a fact with no reader.
output "reserved_tenants" {
  value       = local.reserved_tenants
  description = "Tenant names this module writes itself, for the console to add to its datasources."
}
