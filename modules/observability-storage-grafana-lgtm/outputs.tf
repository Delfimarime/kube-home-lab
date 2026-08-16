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
