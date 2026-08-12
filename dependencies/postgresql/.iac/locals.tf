locals {
  # Pinned exactly. An upgrade is a deliberate edit.
  #
  # 18.4 was the current release when the chart was written. Bumping the minor is safe;
  # bumping the major moves PGDATA to a differently-named directory and is a dump and
  # restore, not a tag edit — see helm/templates/statefulset.yaml.
  postgres_version = "18.4"

  # One element today. It stays a list because ADR 005 makes adding a chart a list entry
  # rather than a resource-kind migration. Every value is a string — the generator carries
  # nothing else, and none of them may be empty: the provider's elements are a TypeMap, whose
  # empty-string entries are dropped before reaching Argo CD, leaving `{{ .values }}` with no
  # key to resolve. `{}` is an empty Helm values mapping and survives the round trip.
  charts = [
    {
      name      = var.cluster_name
      repo_url  = var.chart.repo_url
      path      = var.chart.path
      revision  = var.chart.revision
      namespace = var.namespace
      values    = yamlencode(local.postgresql_values)
    },
  ]

  postgresql_values = {
    fullnameOverride = var.cluster_name
    image            = { tag = local.postgres_version }

    # No password here. The chart generates one into `<cluster_name>`, and the Application
    # below is what stops the next render overwriting it.
    auth = {
      database = var.initdb.database
      username = var.initdb.owner
    }

    service = {
      type     = var.service.type
      nodePort = var.service.node_port
    }

    persistence = {
      size         = var.storage.size
      storageClass = var.storage.storage_class
    }

    parameters = {
      max_connections = tostring(var.max_connections)
    }

    resources = var.resources
    affinity  = var.affinity
  }
}
