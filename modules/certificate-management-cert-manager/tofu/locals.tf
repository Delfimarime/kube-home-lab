locals {
  # These formulas are the chart's `_helpers.tpl`, restated. The Helm release name is the
  # generated Application's name, so the two agree by construction — but if you change one,
  # change the other, or this module publishes a Secret name that does not exist.
  release = "lab-pki"

  ca_secret_names = {
    for name, _ in var.certificate_authorities :
    name => "${local.release}-${name}-ca"
  }

  certificate_secret_names = {
    for name, _ in var.certificate_authorities :
    name => "${local.release}-${name}-tls"
  }

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
  })

  # trust-manager reads a Bundle's sources from its trust namespace, which defaults to
  # "cert-manager" and is not where the authorities live. Its own CRDs default to enabled.
  trust_manager_values = yamlencode({
    app = {
      trust = {
        namespace = var.namespace
      }
      # Not app.webhook.service — that path exists and takes no servicemonitor, and the chart's
      # values schema is what said so. Two charts from the same vendor put the same switch in
      # two different places; this is why ADR 010 pins versions exactly and why the round-trip
      # check renders against the real chart rather than trusting the key.
      metrics = {
        service = {
          servicemonitor = {
            enabled = var.metrics.enabled
          }
        }
      }
    }
  })

  # The chart's values mirror the Terraform variable shape, camel-cased. Nothing is computed
  # here that the chart could compute itself — the module passes intent, the chart renders it.
  lab_pki_values = yamlencode({
    namespace = var.namespace
    authorities = {
      for name, a in var.certificate_authorities :
      name => {
        commonName = a.common_name
        duration   = a.duration
        certificate = merge(
          { usages = a.certificate.usages, duration = a.certificate.duration },
          a.certificate.common_name == null ? {} : { commonName = a.certificate.common_name },
          length(a.certificate.dns_names) == 0 ? {} : { dnsNames = a.certificate.dns_names },
          a.certificate.renew_before == null ? {} : { renewBefore = a.certificate.renew_before },
        )
      }
    }
    trustBundle = {
      name        = var.trust_bundle.name
      authorities = var.trust_bundle.authorities
    }
    gateway = var.gateway_namespace == null ? null : {
      namespace = var.gateway_namespace
    }
  })

  # One static entry per chart, even though two of the three come from the same registry
  # (ADR 005). The waves are load-bearing and not cosmetic: cert-manager's CRDs must exist
  # before trust-manager declares a webhook Certificate against them, and both controllers must
  # be running before lab-pki declares an Issuer.
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
      repo_url    = var.lab_pki.repo_url
      chart       = ""
      path        = var.lab_pki.path
      revision    = var.lab_pki.revision
      namespace   = var.namespace
      wave        = "2"
      values      = local.lab_pki_values
    },
  ]
}
