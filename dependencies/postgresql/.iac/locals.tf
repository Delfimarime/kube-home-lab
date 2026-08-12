locals {
  # Pinned exactly. An upgrade is a deliberate edit.
  #
  # 18.4 was the current release when the chart was written. Bumping the minor is safe;
  # bumping the major moves PGDATA to a differently-named directory and is a dump and
  # restore, not a tag edit — see helm/templates/statefulset.yaml.
  postgres_version = "18.4"

  # Same rule. 1.1.7 ships CloudBeaver 26.1.2. There is no official CloudBeaver chart — this
  # is the only maintained one, so the pin is what keeps a third party's values schema from
  # changing under us.
  cloudbeaver_chart_version = "1.1.7"
  cloudbeaver_repository    = "https://avistotelecom.github.io/charts/"

  # Two elements, two kinds of source: PostgreSQL's chart is in this repository and is read
  # from git, CloudBeaver's comes from a chart repository. `source_kind` is what the template
  # branches on — Argo CD rejects a source carrying both `path` and `chart`.
  #
  # Every value is a string, and none may be empty: the provider's elements are a TypeMap,
  # whose empty-string entries are dropped before reaching Argo CD, leaving `{{ .values }}`
  # with no key to resolve. `{}` is an empty Helm values mapping and survives the round trip.
  # A key absent from one element is fine so long as the template only reads it inside the
  # matching branch, which is why `path` and `chart` do not need placeholders.
  charts = concat(
    [
      {
        name        = var.cluster_name
        source_kind = "git"
        repo_url    = var.chart.repo_url
        path        = var.chart.path
        revision    = var.chart.revision
        namespace   = var.namespace
        values      = yamlencode(local.postgresql_values)
      },
    ],
    var.cloudbeaver.enabled ? [
      {
        name        = "cloudbeaver"
        source_kind = "helm"
        repo_url    = local.cloudbeaver_repository
        chart       = "cloudbeaver"
        revision    = local.cloudbeaver_chart_version
        namespace   = var.namespace
        values      = yamlencode(local.cloudbeaver_values)
      },
    ] : []
  )

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

  cloudbeaver_values = {
    fullnameOverride = "cloudbeaver"

    # Deliberately no affinity: it reaches PostgreSQL by Service DNS, which resolves from any
    # node, so nothing ties it to kube-1. Its own PVC still lands on whichever node it is
    # first scheduled to and the Pod follows it from then on — that is local-path's doing, not
    # a scheduling decision, and not worth restating as one.
    persistence = {
      size         = var.cloudbeaver.storage.size
      storageClass = var.cloudbeaver.storage.storage_class
    }

    # The chart reads the route's hostname from this top-level key, not from httpRoute.
    hostname = var.cloudbeaver.gateway == null ? "" : var.cloudbeaver.gateway.hostname

    httpRoute = {
      enabled = var.cloudbeaver.gateway != null
      # Null attributes are filtered rather than emitted: `sectionName: null` would reach the
      # HTTPRoute verbatim through the chart's toYaml.
      parentRefs = var.cloudbeaver.gateway == null ? [] : [
        {
          for key, value in {
            name        = var.cloudbeaver.gateway.name
            namespace   = var.cloudbeaver.gateway.namespace
            sectionName = var.cloudbeaver.gateway.section_name
          } : key => value if value != null
        }
      ]
    }
  }
}
