locals {
  release = "keycloak"

  # The chart this module renders, published from this repository's own `helm/` tree rather than
  # owned by this module — so its values schema is the chart's and a second consumer is allowed.
  # A constant rather than an input: the only correct value is this one, and a caller able to
  # change it could only ever point an Application at a path that does not exist.
  instance_chart_path = "helm/keycloak-instance"

  # Upstream's manifests, which are not a chart and are not this repository's. Both are constants
  # for the same reason the path above is — there is one correct value for each. Only the tag
  # moves, and it is `var.keycloak.version`.
  #
  # The namespaced kustomization rather than `kubernetes/cluster-wide`: this module puts one
  # Keycloak in one namespace, and the operator only needs to watch that one. Its CRDs are
  # cluster-scoped either way, so the choice bounds the controller's reach and not the CRDs'.
  operator_repo_url = "https://github.com/keycloak/keycloak-k8s-resources"
  operator_path     = "kubernetes"

  # Keycloak ships exactly one realm and this module creates none, so there is one correct value
  # and an input for it would be a knob with a single setting. The day an environment creates a
  # second realm in the console, this becomes an input — and `issuer_url` has to move with it.
  realm = "master"

  # One string, three readers: the route's hostname, the server's own hostname, and the issuer.
  # **The server is given the full URL and not the bare host.** The field takes either, and the
  # bare form leaves Keycloak resolving scheme and port from request headers on every call —
  # behind a Gateway terminating TLS at 443 and speaking HTTP onward, that is the difference
  # between an issuer that is fixed and one that is whatever the last hop claimed.
  #
  # Because both are built here, the discovery document's `issuer` and the output below cannot
  # disagree.
  base_url      = "https://${var.gateway.hostname}"
  issuer_url    = "${local.base_url}/realms/${local.realm}"
  discovery_url = "${local.issuer_url}/.well-known/openid-configuration"

  # The Service the operator creates, named here rather than inferred. Left unset it would default
  # to the resource's name plus `-service`, and this chart's HTTPRoute would have to restate that
  # convention to find it — two places that must agree about a string neither of them owns.
  # Setting it makes the name this chart's, and the route reads the same value.
  service_name = "${local.release}-service"
  service_port = 8080

  # A JDBC URL rather than the resource's host/port/database fields, because `sslmode` has no home
  # among them. Setting `url` makes the other three ignored, so they are not set at all.
  db_url = "jdbc:postgresql://${var.database.host_port}/${var.database.database_name}?sslmode=${var.database.sslmode}"

  # Each credential's name, and whether this module is the one rendering it. Absence of a name is
  # the trigger rather than a flag, so there is no configuration in which this module both renders
  # a placeholder and points somewhere else.
  db_secret_name    = coalesce(var.database.secret_name, "${local.release}-db")
  admin_secret_name = coalesce(var.bootstrap_admin_secret_name, "${local.release}-bootstrap-admin")

  render_db_secret    = var.database.secret_name == null
  render_admin_secret = var.bootstrap_admin_secret_name == null

  # The keys the workload reads. The database's are the caller's to name, because the resource
  # takes a key beside each Secret reference. The administrator's are not — the operator reads
  # `username` and `password` by fixed name, so these are stated here rather than derived from
  # inputs that would have exactly one correct value.
  db_secret_keys    = [var.database.username_key, var.database.password_key]
  admin_secret_keys = ["username", "password"]

  # Stated as a label the collector discovers rather than as anything this module sends: a scrape
  # has no request behind it to carry a header, so what a pushing workload says per request a
  # scraped one says once, here.
  #
  # **On the Service and on the pods, and the two are not redundant.** Metrics are discovered
  # through the Service a ServiceMonitor selects; logs are discovered from pods, where no Service
  # exists to be read. A label on only one of them routes only one of the two signals.
  #
  # Two traps live in how the chart writes them, both recorded there: the field that labels the
  # Service is `http.labels` rather than the `serviceMonitor.labels` whose description claims it,
  # and the only field that labels the pods is under `unsupported`.
  tenant_label  = "opentelemetry.io/tenant"
  tenant_labels = var.metrics.tenant == null ? {} : { (local.tenant_label) = var.metrics.tenant }

  instance_values = yamlencode({
    name  = local.release
    image = var.keycloak.image

    service = {
      name = local.service_name
      port = local.service_port
    }

    hostname = local.base_url

    database = {
      url         = local.db_url
      secretName  = local.db_secret_name
      usernameKey = var.database.username_key
      passwordKey = var.database.password_key
    }

    bootstrapAdmin = {
      secretName = local.admin_secret_name
    }

    route = {
      hostname = var.gateway.hostname
      gateway = {
        name        = var.gateway.name
        namespace   = var.gateway.namespace
        sectionName = var.gateway.section_name
      }
    }

    metrics = {
      enabled = var.metrics.enabled
      labels  = local.tenant_labels
    }
  })

  # One static entry per source, as a List generator requires even at one. Each credential's
  # element comes from the shared module and is an empty list when this module was given that
  # name — there is then nothing to render and nothing to own.
  #
  # The waves are load-bearing. The operator's CRDs must exist before anything declares a
  # `Keycloak`, and the Secrets must exist before the server starts looking for a password —
  # empty is enough for the pod to be scheduled, and the values are read at start and do not
  # reload, which is why the spec says to restart after filling them.
  #
  # `chart` is present and empty on both entries below because a List generator's elements must
  # agree on their keys, and the shared credential module emits one. Nothing here reads it: every
  # source in this module is read from git, so there is no chart-registry branch to guard.
  charts = concat(
    module.database_credentials[*].element,
    module.bootstrap_admin_credentials[*].element,
    [
      {
        name        = "keycloak-operator"
        source_kind = "kustomize"
        repo_url    = local.operator_repo_url
        chart       = ""
        path        = local.operator_path
        revision    = var.keycloak.version
        namespace   = var.namespace
        wave        = "0"
        values      = ""
      },
      {
        name        = local.release
        source_kind = "git"
        repo_url    = var.git_repository.url
        chart       = ""
        path        = local.instance_chart_path
        revision    = var.git_repository.revision
        namespace   = var.namespace
        wave        = "1"
        values      = local.instance_values
      },
    ],
  )
}
