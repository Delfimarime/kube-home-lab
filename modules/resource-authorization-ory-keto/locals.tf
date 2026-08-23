locals {
  # The chart this module renders, published from this repository's own `helm/` tree rather than
  # owned by this module — so its values schema is the chart's and a second consumer is allowed. A
  # constant rather than an input: the only correct value is this one, and a caller able to change
  # it could only ever point an Application at a path that does not exist.
  chart_path = "helm/ory-keto"

  # The Application's name is also its Helm release name, so every object the chart renders is
  # named after the thing an operator is looking for — which is what makes `rollout restart
  # deployment/keto` the obvious command rather than one that has to be looked up.
  release = "keto"

  # The Services the wrapped chart creates, named from the release. Stated here and read back into
  # the addresses below rather than the naming rule being reproduced — a copy of somebody else's
  # convention goes stale the day they change it, and the only symptom is an address nothing
  # answers on.
  read_service  = "${local.release}-read"
  write_service = "${local.release}-write"

  # **Port 80, and not 4466/4467.** Those are the container's ports, which is what the
  # NetworkPolicy names because a policy applies at the pod. The Services in front of them listen
  # on 80, which is what a consumer dials.
  service_port = 80

  # The ports the policy names — the container's. Constants for the same reason the path is: the
  # store serves its read API on one and its write API on the other, and neither is a choice.
  container_port_read  = 4466
  container_port_write = 4467

  # How the policy finds the store's pods. The wrapped chart labels them with its own chart name,
  # and this module never sets `nameOverride`, so this is that name.
  store_pod_selector = { "app.kubernetes.io/name" = "keto" }

  # Two addresses, published because they are two trust levels. A consumer holding the read address
  # cannot write no matter what it does with it.
  read_url  = "http://${local.read_service}.${var.namespace}.svc.cluster.local:${local.service_port}"
  write_url = "http://${local.write_service}.${var.namespace}.svc.cluster.local:${local.service_port}"

  # The credential's name, and whether this module is the one rendering it. Absence of a name is
  # the trigger rather than a flag, so there is no configuration in which this module both renders
  # a placeholder and points somewhere else.
  #
  # The name is fixed rather than derived because nothing publishes it: an operator reads it from
  # the spec and types it into a `kubectl patch`.
  db_secret_name   = coalesce(var.database_secret_name, "${local.release}-db-credentials")
  render_db_secret = var.database_secret_name == null

  # One key, holding the whole connection string. The chart reads `DSN` from it by that fixed name,
  # so the host, the database and the sslmode all live inside the value an operator types — which
  # is why none of them is an input here.
  db_secret_keys = ["dsn"]

  # ---------------------------------------------------------------- the model
  #
  # Either a model somebody wrote, passed through, or one generated from the structured form. The
  # variable's validations guarantee at most one is set, so nothing here has to arbitrate.
  #
  # **The generated form is a bounded subset of the language**: one level of composition, three
  # kinds of term, no negation. That bound is the whole reason `content` exists beside it — the
  # escape hatch is the feature, not an admission.
  model_namespaces = try(var.model.namespaces, null)

  # `Group#members` is the compact spelling of a subject set, which reads the way a tuple is
  # written. Every distinct token is translated once, here, rather than at each use.
  opl_type_tokens = local.model_namespaces == null ? {} : {
    for tok in distinct(flatten([
      for ns, spec in local.model_namespaces : [for r, types in spec.relations : types]
      ])) : tok => (
      length(split("#", tok)) == 1
      ? tok
      : format("SubjectSet<%s, \"%s\">", split("#", tok)[0], split("#", tok)[1])
    )
  }

  # Keys are sorted at every level so the same input renders the same bytes. Unsorted, a map's
  # iteration order would make the ConfigMap's content churn between plans and every sync would
  # look like a change to the permission model.
  opl_related = local.model_namespaces == null ? {} : {
    for ns, spec in local.model_namespaces : ns => (
      length(spec.relations) == 0 ? [] : concat(
        ["  related: {"],
        [for r in sort(keys(spec.relations)) : format(
          "    %s: %s[]", r,
          length(spec.relations[r]) == 1
          ? local.opl_type_tokens[spec.relations[r][0]]
          : format("(%s)", join(" | ", [for t in spec.relations[r] : local.opl_type_tokens[t]]))
        )],
        ["  }"],
      )
    )
  }

  opl_permits = local.model_namespaces == null ? {} : {
    for ns, spec in local.model_namespaces : ns => (
      length(spec.permits) == 0 ? [] : concat(
        ["  permits = {"],
        flatten([for p in sort(keys(spec.permits)) : [
          format("    %s: (ctx: Context): boolean =>", p),
          format("      %s,", join(
            spec.permits[p].all_of != null ? " &&\n      " : " ||\n      ",
            [for t in(spec.permits[p].all_of != null ? spec.permits[p].all_of : spec.permits[p].any_of) : (
              t.traverse != null
              ? format("this.related.%s.traverse((v) => v.permits.%s(ctx))", t.traverse.relation, t.traverse.permit)
              : t.permit != null
              ? format("this.permits.%s(ctx)", t.permit)
              : format("this.related.%s.includes(ctx.subject)", t.relation)
            )]
          )),
        ]]),
        ["  }"],
      )
    )
  }

  # A namespace with neither relations nor permits is a bare subject type — the shape `User`
  # almost always has — and it reads better on one line than as an empty block.
  opl_classes = local.model_namespaces == null ? [] : [
    for ns in sort(keys(local.model_namespaces)) : (
      length(local.opl_related[ns]) == 0 && length(local.opl_permits[ns]) == 0
      ? format("class %s implements Namespace {}", ns)
      : join("\n", concat(
        [format("class %s implements Namespace {", ns)],
        local.opl_related[ns],
        length(local.opl_related[ns]) > 0 && length(local.opl_permits[ns]) > 0 ? [""] : [],
        local.opl_permits[ns],
        ["}"],
      ))
    )
  ]

  # All three names are imported whether or not this model uses each: the import list is not worth
  # deriving, and an unused one costs nothing in a language whose parser only reads declarations.
  generated_model = local.model_namespaces == null ? null : join("\n\n", concat(
    ["import { Namespace, SubjectSet, Context } from \"@ory/permission-namespace-types\""],
    local.opl_classes,
  ))

  model_content = try(var.model.content, null) != null ? var.model.content : local.generated_model

  # ------------------------------------------------------------------- values
  #
  # The values handed to the chart. **No credential is among them.** `secret.enabled = false` with
  # a name is precisely how the chart is told to read `DSN` from a Secret it does not own; setting
  # `keto.config.dsn` instead would put a password into the Helm values rendered inside an
  # Application spec, which sits in etcd in plaintext readable by anyone who can read that object.
  store_values = yamlencode({
    # `content` is omitted rather than sent as null when no model was given, so the chart's own
    # default survives the merge. A null written here would override that default with nothing and
    # the store would start against an empty file, which is a parse error rather than a store with
    # nothing to say.
    model = merge(
      { configMapName = "${local.release}-permission-model" },
      local.model_content == null ? {} : { content = local.model_content },
    )

    # Sorted, so a plan that changes nothing renders nothing. A map's iteration order is not part
    # of its value, and an unsorted list here would reorder the policy's rules between plans.
    writeAccessFrom = [
      for k in sort(keys(var.write_access_from)) : {
        namespace = var.write_access_from[k].namespace
        labels    = var.write_access_from[k].labels
      }
    ]

    ports = {
      read  = local.container_port_read
      write = local.container_port_write
    }

    podSelector = local.store_pod_selector

    keto = {
      # `fullnameOverride` rather than letting the release name flow through: the Services are
      # addressed by the names derived above, and stating the stem here is what makes those
      # addresses this module's rather than a convention it copied.
      fullnameOverride = local.release

      secret = {
        # The chart creates no Secret and reads the named one instead. Both halves matter: with
        # `enabled` left true it would generate its own and the operator would fill in the wrong
        # object.
        enabled      = false
        nameOverride = local.db_secret_name
      }

      # The store's own configuration. `dsn` is deliberately absent — see above.
      keto = {
        config = {
          serve = {
            read  = { port = local.container_port_read }
            write = { port = local.container_port_write }
          }
        }
      }

      serviceMonitor = {
        enabled = var.metrics.enabled
      }

      # The tenant this workload's telemetry is stored under, written where the collector
      # discovers it. **Only the pods carry it.** The wrapped chart's service block takes
      # annotations and no labels, so the Services cannot be labelled without re-authoring them —
      # which would make this a fork rather than a wrapper. Metrics scraped from the pods are
      # routed correctly; anything routing on the Service's label is not.
      deployment = {
        podMetadata = {
          labels = var.metrics.tenant == null ? {} : { "opentelemetry.io/tenant" = var.metrics.tenant }
        }
      }
    }
  })

  # Every element the List generator gets. The credential first, so the Secret exists before the
  # store that mounts it — `count` on the module call is what makes "no name given" mean "no
  # element" rather than an element that renders nothing.
  charts = concat(
    [for m in module.database_credentials : m.element],
    [{
      name        = local.release
      source_kind = "git"
      repo_url    = var.git_repository.url
      chart       = ""
      path        = local.chart_path
      revision    = var.git_repository.revision
      namespace   = var.namespace
      wave        = "1"
      values      = local.store_values
    }],
  )
}
