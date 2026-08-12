locals {
  # Pinned exactly. An upgrade is a deliberate edit.
  operator_chart_version = "0.29.0" # CloudNativePG 1.30.0
  cluster_chart_version  = "0.8.1"
  postgres_image         = "ghcr.io/cloudnative-pg/postgresql:18" # chart still defaults to 16
  chart_repository       = "https://cloudnative-pg.github.io/charts"

  # List generator elements. Every value is a string — the generator carries nothing else, and
  # none of them may be empty: the provider's elements are a TypeMap, whose empty-string entries
  # are dropped before reaching Argo CD, leaving `{{ .values }}` with no key to resolve. `{}` is
  # an empty Helm values mapping and survives the round trip.
  charts = [
    {
      name      = "cloudnative-pg"
      chart     = "cloudnative-pg"
      version   = local.operator_chart_version
      namespace = var.operator_namespace
      values    = "{}"
    },
    {
      name      = var.cluster_name
      chart     = "cluster"
      version   = local.cluster_chart_version
      namespace = var.namespace
      values    = yamlencode(local.cluster_values)
    },
  ]

  cluster_values = {
    fullnameOverride = var.cluster_name
    backups          = { enabled = false }
    cluster = {
      instances = 1
      imageName = local.postgres_image
      storage = {
        size         = var.storage.size
        storageClass = var.storage.storage_class
      }
      resources = var.resources
      affinity  = var.affinity
      # Single instance: a PDB only blocks node drains, and no consumer needs the superuser.
      enablePDB             = false
      enableSuperuserAccess = false
      postgresql = {
        parameters = {
          # CNPG defaults this to logical; nothing here replicates.
          wal_level       = "replica"
          max_connections = tostring(var.max_connections)
        }
      }
      # No `secret` — the operator generates `<cluster_name>-app` with username, password,
      # host, port and dbname. A named Secret would have to exist already.
      initdb = {
        database = var.initdb.database
        owner    = var.initdb.owner
      }
    }
  }
}
