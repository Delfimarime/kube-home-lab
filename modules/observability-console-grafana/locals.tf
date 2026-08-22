locals {
  # The workload, the Helm release, the Application and the Service all carry this one name, so a
  # route pointing at a Service and an Application named for what it renders agree by construction.
  release = "grafana"

  # The label a collector reads a workload's tenant from. Spelled out here rather than taken as an
  # input: the name is a platform contract, and an input for it would be a second place to spell it.
  tenant_label  = "opentelemetry.io/tenant"
  tenant_labels = var.metrics.tenant == null ? {} : { (local.tenant_label) = var.metrics.tenant }

  # Three credentials, one rule. A name was given, or this module renders a placeholder for it.
  # Both branches produce a name; only one produces an object. The third exists only when an issuer
  # is wired at all, because a client secret with no client is a Secret nothing would ever read.
  render_database_secret = var.database.secret_name == null
  render_admin_secret    = var.admin.secret_name == null
  render_oidc_secret     = var.oidc != null && try(var.oidc.secret_name, null) == null

  database_secret_name = coalesce(var.database.secret_name, "grafana-db-credentials")
  admin_secret_name    = coalesce(var.admin.secret_name, "grafana-admin-credentials")
  oidc_secret_name     = var.oidc == null ? null : coalesce(var.oidc.secret_name, "grafana-oidc-credentials")

  # The keys each placeholder carries are the same ones the configuration below reads, so every
  # object has exactly the keys the pod looks for. A Secret with the right name and the wrong keys
  # is the failure this removes, and it is the one that reads as a broken module.
  database_secret_keys = [var.database.username_key, var.database.password_key]
  admin_secret_keys    = [var.admin.user_key, var.admin.password_key]
  oidc_secret_keys     = var.oidc == null ? [] : [var.oidc.secret_key]

  # The key trust-manager writes the bundle under. A constant rather than an input: the ConfigMap
  # and its key are one object's shape, and a caller able to change one without the other could
  # only ever mount a path that does not exist.
  trust_bundle_key = "ca-certificates.crt"

  # Where the bundle is mounted, and it is not an arbitrary path: replacing the image's own
  # certificate file is what makes Grafana's HTTP client trust the lab authority, and the bundle
  # carries the public roots alongside it so nothing else stops being trusted.
  trust_bundle_path = "/etc/ssl/certs/ca-certificates.crt"

  # Grafana's roles, and the claim they are read from. The slug is the OIDC client ID, so a role
  # named for anything else names an object the token does not carry.
  roles_claim = var.oidc == null ? null : coalesce(var.oidc.groups_claim, "resource_access.grafana.roles")

  # **JMESPath, not JSONPath, and this is the most likely thing to get wrong.** A JSONPath-style
  # `$.resource_access...` prefix is syntactically accepted and matches nothing, which under strict
  # mode refuses every login — a failure that looks like a broken issuer rather than a broken
  # expression. `Editor` is deliberately unmapped: two roles, and a third would be a third clause
  # here and nothing else.
  role_attribute_path = var.oidc == null ? null : join("", [
    "contains(${local.roles_claim}[*], 'GRAFANA_ADMIN') && 'Admin'",
    " || contains(${local.roles_claim}[*], 'GRAFANA_VIEWER') && 'Viewer'",
    " || ''",
  ])

  # Grafana's generic OAuth takes three endpoint URLs and reads no discovery document, while the
  # input carries only the issuer's address — so the endpoints are assembled here, at the paths an
  # OpenID Connect issuer publishes them under. Change the issuer for one that lays them out
  # differently and this is the line that moves.
  issuer      = var.oidc == null ? null : trimsuffix(var.oidc.issuer_url, "/")
  oidc_prefix = var.oidc == null ? null : "${local.issuer}/protocol/openid-connect"

  # Where Grafana is reachable from a browser, which is also the redirect URI its OIDC client must
  # be registered with. null when nothing routes it.
  grafana_url = var.gateway == null ? null : "https://${var.gateway.hostname}"

  # The three stores, keyed by the capability rather than by the product behind it. A datasource's
  # type follows from which address it is and is not an input: swapping a store means swapping it
  # for something speaking the same query API.
  stores = {
    metrics = { type = "prometheus", url = var.metrics_url }
    logs    = { type = "loki", url = var.logs_url }
    traces  = { type = "tempo", url = var.traces_url }
  }

  present = { for name, store in local.stores : name => store if store.url != null }

  # **Grafana permits one default datasource per organization, not one per type.** Marking the
  # default tenant's metrics, logs and traces all default is three defaults in one file, which
  # Grafana refuses whole — `Only one datasource per organization can be marked as default` — and it
  # then starts with no provisioned datasources at all rather than with the two it did not object to.
  #
  # Metrics where there are metrics, because that is what Explore opens on and what a dashboard
  # panel with no datasource named falls back to; otherwise whichever store this environment does
  # ship. The list is ordered, and at least one entry survives because at least one address is
  # required.
  default_store = [for name in ["metrics", "logs", "traces"] : name if contains(keys(local.present), name)][0]

  # One identifier per store per tenant, computed for all three whether or not their address was
  # given: a correlation link names the identifier of the datasource at its far end, and the link
  # is what checks that end exists, not this map.
  uids = {
    for name, _ in local.stores : name => {
      for tenant in var.tenants : tenant => "${name}-${tenant}"
    }
  }

  # **Every read carries the tenant as a header, not as a second address.** The stores are
  # multi-tenant and nothing validates the header, so the tenant is a routing fact rather than a
  # credential — which is why it sits in the provisioning file in the open. Grafana still requires
  # header *values* under secureJsonData, so that is where it goes.
  #
  # **Each correlation link is conditional on both of its ends existing**, and both ends are two of
  # the three addresses being non-null. Every link is wired within one tenant: a trace in one
  # tenant cannot open logs in another, which is the cost of partitioning writes, paid on the read
  # side.
  datasources = flatten([
    for name, store in local.present : [
      for tenant in var.tenants : {
        name   = "${name} ${tenant}"
        uid    = local.uids[name][tenant]
        type   = store.type
        access = "proxy"
        url    = store.url

        # Exactly one datasource in this file is the default: one tenant's, one store's. Deriving
        # either from list ordering is the kind of implicit rule that is obvious to whoever wrote it
        # and to nobody else.
        isDefault = tenant == var.default_tenant && name == local.default_store

        # A provisioned datasource is rewritten from this file every time Grafana starts, so an
        # edit made in the UI is a change that silently disappears on the next restart. Saying so
        # here turns that into a field the UI refuses rather than a surprise.
        editable = false

        jsonData = merge(
          {
            httpHeaderName1 = "X-Scope-OrgID"
          },

          # A point on a graph opens the trace it came from.
          name == "metrics" && var.traces_url != null ? {
            exemplarTraceIdDestinations = [{
              name          = "trace_id"
              datasourceUid = local.uids["traces"][tenant]
            }]
          } : {},

          # A log line opens its trace. The match is on the trace identifier carried beside the
          # line rather than on a pattern inside it, because a regular expression over log text
          # only works for whichever format happened to be tried.
          name == "logs" && var.traces_url != null ? {
            derivedFields = [{
              name            = "TraceID"
              matcherType     = "label"
              matcherRegex    = "trace_id"
              datasourceUid   = local.uids["traces"][tenant]
              url             = "$${__value.raw}"
              urlDisplayLabel = "Trace"
            }]
          } : {},

          # A span opens its logs, within its own tenant and around its own time window.
          name == "traces" && var.logs_url != null ? {
            tracesToLogsV2 = {
              datasourceUid      = local.uids["logs"][tenant]
              spanStartTimeShift = "-1h"
              spanEndTimeShift   = "1h"
              filterByTraceID    = true
              filterBySpanID     = false
            }
          } : {},

          # The service graph, and half of it is somebody else's job: the trace store's
          # metrics-generator derives the request counters from spans as they arrive and writes
          # them into the metrics store, and only when both are on. With no metrics address that
          # half never happened either, so leaving this unset is what keeps the tab from offering
          # a query nothing can answer.
          name == "traces" && var.metrics_url != null ? {
            serviceMap = {
              datasourceUid = local.uids["metrics"][tenant]
            }
          } : {},
        )

        secureJsonData = {
          httpHeaderValue1 = tenant
        }
      }
    ]
  ])

  # Grafana's own configuration file. **Nothing sensitive is in it**, and that is checked twice:
  # the credential and the client secret arrive as environment variables read from Secrets, and
  # the chart itself refuses to render a password or a client secret written in here.
  grafana_ini = merge(
    {
      # No SQLite fallback and no volume: everything a person creates in this console — users,
      # preferences, annotations and every alert rule — lives in PostgreSQL, which is also the only
      # thing here that cannot be regenerated from git.
      database = {
        type     = "postgres"
        host     = var.database.host_port
        name     = var.database.database_name
        ssl_mode = var.database.sslmode
      }

      # **The login form follows the issuer and nothing else.** Wired, the form closes and the one
      # account is the only way in through a browser; unwired, the form is the only way in at all.
      # Two states derived from one input, with nothing to configure and nothing to get wrong.
      #
      # What that leaves when the issuer is down: the form is gone, but Grafana's admin account
      # still exists in PostgreSQL and still authenticates to the HTTP API with basic auth. That is
      # the break-glass route — unadvertised rather than absent, and worth knowing before an outage
      # rather than during one.
      auth = {
        disable_login_form = var.oidc != null
      }
    },

    # Grafana builds its redirect URI from this, so a console behind a Gateway that is left to the
    # default advertises its own pod port and the callback lands nowhere.
    local.grafana_url == null ? {} : {
      server = {
        root_url = "${local.grafana_url}/"
      }
    },

    var.oidc == null ? {} : {
      "auth.generic_oauth" = {
        enabled   = true
        name      = "OpenID Connect"
        client_id = var.oidc.client_id
        scopes    = join(" ", var.oidc.scopes)

        auth_url  = "${local.oidc_prefix}/auth"
        token_url = "${local.oidc_prefix}/token"
        api_url   = "${local.oidc_prefix}/userinfo"

        role_attribute_path = local.role_attribute_path

        # **This is what turns "no role" into a refused login rather than a silent default.**
        # Without it a token carrying no recognised role falls through to Grafana's default org
        # role and the person is in — which is the opposite of what the claim is being read for.
        role_attribute_strict = true

        # Server administration is not something a claim can grant. There is one organisation and
        # one operator; delegating it buys nothing and widens what a misconfigured issuer can do.
        allow_assign_grafana_admin = false

        # An account is created on first sign-in. Nothing is admitted by it: the strict role check
        # above runs first, so a person with no recognised role gets neither a session nor a row.
        allow_sign_up = true

        use_pkce = true
      }
    },

    # An override lands last, one section at a time. This file is the only place a top-level
    # replacement would be actively dangerous — it carries the database wiring, the login form's
    # state and the whole OIDC configuration — so an override adding `smtp` keeps them, and one
    # naming a section this module wrote replaces that section alone.
    try(var.grafana.values["grafana.ini"], {}),
  )

  # The client secret and the database credential reach the process as environment variables read
  # from Secrets, so neither value appears in a values.yaml, in a rendered Application spec, or in
  # state. Grafana reads GF_<SECTION>_<KEY> in preference to the file above, which is what makes
  # the two halves of one setting land in the same place.
  env_value_from = merge(
    {
      GF_DATABASE_USER = {
        secretKeyRef = {
          name = local.database_secret_name
          key  = var.database.username_key
        }
      }
      GF_DATABASE_PASSWORD = {
        secretKeyRef = {
          name = local.database_secret_name
          key  = var.database.password_key
        }
      }
    },
    var.oidc == null ? {} : {
      GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET = {
        secretKeyRef = {
          name = local.oidc_secret_name
          key  = var.oidc.secret_key
        }
      }
    },
  )

  # The administrator account, read from a Secret rather than made up by the chart. Naming one here
  # is also what stops the chart rendering an admin Secret of its own, so there is exactly one
  # object holding this credential and exactly one thing that decided its value: a person.
  admin_values = {
    existingSecret = local.admin_secret_name
    userKey        = var.admin.user_key
    passwordKey    = var.admin.password_key
  }

  # Mounted only when an issuer is wired, because that is the only thing here making a
  # server-to-server call over TLS. The ConfigMap is created by the certificate module and is
  # already in this namespace; this module mounts it and never creates it.
  trust_bundle_mounts = var.oidc == null ? [] : [{
    name      = "trust-bundle"
    mountPath = local.trust_bundle_path
    subPath   = local.trust_bundle_key
    configMap = var.trust_bundle_name
    readOnly  = true
  }]

  # The route, rendered by Grafana's own chart from its own values — no wrapper chart and no
  # manifest created outside the Application. A Gateway that was not given produces no route at
  # all, and that, and nothing else, is what "not exposed" means here.
  # Zero or one entries, which is what lets the two fields below be written once instead of twice.
  routable = { for name, gateway in { main = var.gateway } : name => gateway if gateway != null }

  route_main = {
    enabled   = var.gateway != null
    hostnames = [for gateway in local.routable : gateway.hostname]
    parentRefs = [
      for gateway in local.routable : merge(
        {
          name      = gateway.name
          namespace = gateway.namespace
        },
        gateway.section_name == null ? {} : { sectionName = gateway.section_name },
      )
    ]
  }

  # `ingress` is switched off explicitly and stays off: the chart renders both an Ingress and a
  # Gateway route from separate values, and two paths in is one more than anything here needs to
  # reason about. `persistence` likewise — every byte of state is in PostgreSQL, so a volume here
  # would hold nothing and would still have to be scheduled somewhere.
  #
  # **Nothing configures alerting.** Grafana's Unified Alerting is on by its own default and
  # evaluates against whichever datasources exist; rules, contact points and notification policies
  # are authored in the UI and stored in the same PostgreSQL. No second Alertmanager is deployed —
  # Grafana embeds one, and a second would be a second place a rule could be authored. The
  # capability being present and unconfigured is a different thing from it being absent.
  grafana_values = yamlencode(merge(
    {
      fullnameOverride = local.release

      datasources = {
        "datasources.yaml" = {
          apiVersion  = 1
          datasources = local.datasources
        }
      }

      envValueFrom         = local.env_value_from
      extraConfigmapMounts = local.trust_bundle_mounts
      admin                = local.admin_values

      ingress        = { enabled = false }
      route          = { main = local.route_main }
      persistence    = { enabled = false }
      serviceMonitor = { enabled = var.metrics.enabled }

      # The tenant this workload's own telemetry belongs to, stated where the collector discovers
      # it: on the Service its ServiceMonitor selects, and on the pod behind it because logs are
      # discovered from pods and see no Service at all. Empty when no tenant was given, which
      # collects this as the cluster's own.
      podLabels = local.tenant_labels
      service   = { labels = local.tenant_labels }
    },

    # A key given here replaces this module's whole value for that key. It is the setting nobody
    # anticipated, not a supported second layer.
    var.grafana.values,

    # Except this one, which was already merged section by section above and would otherwise be
    # thrown away wholesale by an override that only wanted to add one.
    { "grafana.ini" = local.grafana_ini },
  ))

  # One static entry per chart, as a List generator requires even at one. Each credential's element
  # comes from the shared module and is an empty list when this module was given that name — there
  # is then nothing to render and nothing to own. Between one and four elements, and the count is
  # decided entirely by how many credentials the caller left unnamed.
  #
  # The waves are load-bearing: Grafana reads all three of these before it serves anything, so they
  # have to exist before the workload syncs. Empty is enough for the pod to be scheduled.
  charts = concat(
    module.database_credentials[*].element,
    module.admin_credentials[*].element,
    module.oidc_credentials[*].element,
    [{
      name        = local.release
      source_kind = "helm"
      repo_url    = "https://grafana.github.io/helm-charts"
      chart       = "grafana"
      path        = ""
      revision    = var.grafana.chart_version
      namespace   = var.namespace
      wave        = "1"
      values      = local.grafana_values
    }],
  )
}
