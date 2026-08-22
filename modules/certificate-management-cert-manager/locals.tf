locals {
  release = "cert-pki"

  # Where this module's chart sits inside this repository. A constant rather than an input: the
  # only correct value is this one, and a caller able to change it could only ever point an
  # Application at a path that does not exist.
  chart_path = "modules/certificate-management-cert-manager/helm"

  # `default` is issued from var.domain and is not in var.certificates — the variable refuses that
  # key. Everything downstream reads this map, so the wildcard is an ordinary entry from here on.
  certificates = merge(
    {
      default = {
        mode         = "mtls"
        dns_names    = ["*.${var.domain}"]
        duration     = var.default_certificate.duration
        renew_before = var.default_certificate.renew_before
      }
    },
    {
      for name, c in var.certificates :
      name => {
        mode = c.mode
        # An entry that names no hosts gets the obvious one. Nothing here should require a caller
        # to repeat the domain it already declared.
        dns_names    = length(c.dns_names) > 0 ? c.dns_names : ["${name}.${var.domain}"]
        duration     = c.duration
        renew_before = c.renew_before
      }
    },
  )

  mtls_certificates = {
    for name, c in local.certificates : name => c if c.mode == "mtls"
  }

  # These formulas are the chart's `_helpers.tpl`, restated. The Helm release name is the
  # generated Application's name, so the two agree by construction — but if you change one,
  # change the other, or this module publishes a Secret name that does not exist.
  ca_secret_names = {
    for name in ["server", "client"] :
    name => "${local.release}-${name}-ca"
  }

  certificate_secret_names = {
    for name, _ in local.certificates :
    name => "${local.release}-${name}-tls"
  }

  client_certificate_secret_names = {
    for name, _ in local.mtls_certificates :
    name => "${local.release}-${name}-client"
  }

  # Where a tenant is stated, it is stated as a label the collector discovers rather than as
  # anything this module sends: a scrape has no request behind it to carry a header, so what a
  # pushing workload says per request a scraped one says once, here.
  #
  # **On the Service and on the pods, and the two are not redundant.** Metrics are discovered
  # through the Service a ServiceMonitor selects; logs are discovered from pods, where no Service
  # exists to be read. A label on only one of them routes only one of the two signals.
  #
  # Empty when no tenant is given, which leaves the collector to treat this as the cluster's own
  # telemetry — the same place it went before any of this was configurable.
  tenant_label  = "opentelemetry.io/tenant"
  tenant_labels = var.metrics.tenant == null ? {} : { (local.tenant_label) = var.metrics.tenant }

  # cert-manager: the CRDs are not installed by default, and the flag was renamed from
  # `installCRDs` at v1.15 — the old name is silently ignored rather than rejected, so a version
  # bump that missed it would install a controller with no types to reconcile.
  #
  # clusterResourceNamespace is set explicitly rather than left to default to the release
  # namespace. It already would; stating it is what stops a future move of the controllers into
  # their own namespace from silently detaching every ClusterIssuer from its CA Secret.
  cert_manager_values = yamlencode({
    crds = {
      enabled = true
      keep    = true
    }
    clusterResourceNamespace = var.namespace
    prometheus = {
      enabled = var.metrics.enabled
      servicemonitor = {
        enabled = var.metrics.enabled
      }
    }

    # Three workloads in one chart, each with its own copy of the keys. The controller is the one
    # that emits metrics; the other two are here because all three emit logs.
    podLabels     = local.tenant_labels
    serviceLabels = local.tenant_labels
    webhook = {
      podLabels     = local.tenant_labels
      serviceLabels = local.tenant_labels
    }
    cainjector = {
      podLabels     = local.tenant_labels
      serviceLabels = local.tenant_labels
    }
  })

  # trust-manager reads a Bundle's sources from its trust namespace, which defaults to
  # "cert-manager" and is not necessarily where the authorities live. Its own CRDs default to
  # enabled.
  trust_manager_values = yamlencode({
    app = {
      trust = {
        namespace = var.namespace
      }

      # This chart exposes pod labels and no Service labels, so trust-manager's metrics are
      # discovered through a Service carrying no tenant and fall back to the pod behind it. That is
      # what the fallback is for.
      podLabels = local.tenant_labels
      # Not app.webhook.service — that path exists and takes no servicemonitor, and the chart's
      # values schema is what said so. Two charts from the same vendor put the same switch in two
      # different places, which is why versions are pinned exactly and why the round-trip check
      # renders against the real chart rather than trusting the key.
      metrics = {
        service = {
          servicemonitor = {
            enabled = var.metrics.enabled
          }
        }
      }
    }
  })

  # The module resolves modes into shapes; the chart renders what it is given and has no notion of
  # "mtls". An entry carrying a `client` block is a pair — that presence *is* the mode, so there is
  # no second place where the two could disagree about what mtls means.
  cert_pki_values = yamlencode({
    namespace = var.namespace

    authorities = {
      server = {
        commonName = "${var.domain} server CA"
        duration   = var.authority.duration
      }
      client = {
        commonName = "${var.domain} client CA"
        duration   = var.authority.duration
      }
    }

    certificates = {
      for name, c in local.certificates :
      name => merge(
        {
          server = merge(
            {
              dnsNames = c.dns_names
              duration = c.duration
            },
            c.renew_before == null ? {} : { renewBefore = c.renew_before },
          )
        },
        c.mode != "mtls" ? {} : {
          client = {
            # A client certificate names itself; there is no hostname to name. The subject is an
            # identity label — what authorizes it is the authority that signed it.
            commonName = "${name}.${var.domain}"
            duration   = c.duration
            # Short by default: cert-manager renews at two thirds of lifetime, which would leave
            # the expiry metric describing a certificate nobody has deployed — and a client
            # certificate is the one that lives on a laptop rather than in the cluster.
            renewBefore = coalesce(c.renew_before, "720h")
          }
        },
      )
    }

    trustBundle = {
      name        = var.trust_bundle.name
      authorities = var.trust_bundle.authorities
    }

    gateway = var.gateway_namespace == null ? null : {
      namespace = var.gateway_namespace
    }
  })

  # One static entry per chart, even though two of the three come from the same registry. The
  # waves are load-bearing and not cosmetic: cert-manager's CRDs must exist before trust-manager
  # declares a webhook Certificate against them, and both controllers must be running before
  # cert-pki declares an Issuer.
  charts = [
    {
      name        = "cert-manager"
      source_kind = "helm"
      repo_url    = "https://charts.jetstack.io"
      chart       = "cert-manager"
      path        = ""
      revision    = var.cert_manager.chart_version
      namespace   = var.namespace
      wave        = "0"
      values      = local.cert_manager_values
    },
    {
      name        = "trust-manager"
      source_kind = "helm"
      repo_url    = "https://charts.jetstack.io"
      chart       = "trust-manager"
      path        = ""
      revision    = var.trust_manager.chart_version
      namespace   = var.namespace
      wave        = "1"
      values      = local.trust_manager_values
    },
    {
      name        = local.release
      source_kind = "git"
      repo_url    = var.git_repository.url
      chart       = ""
      path        = local.chart_path
      revision    = var.git_repository.revision
      namespace   = var.namespace
      wave        = "2"
      values      = local.cert_pki_values
    },
  ]
}
