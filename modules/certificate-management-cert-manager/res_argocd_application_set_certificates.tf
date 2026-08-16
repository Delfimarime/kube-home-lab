resource "argocd_application_set" "certificates" {
  metadata {
    name      = "certificate-management"
    namespace = var.argocd.namespace
  }

  spec {
    go_template         = true
    go_template_options = ["missingkey=error"]

    generator {
      list {
        elements = local.charts
      }
    }

    template {
      metadata {
        name = "{{ .name }}"

        # A List generator has no inherent order. Without these the three Applications sync
        # concurrently and cert-manager's CRDs may not exist when trust-manager declares a
        # Certificate against them — a failure that reads as a broken chart.
        annotations = {
          "argocd.argoproj.io/sync-wave" = "{{ .wave }}"
        }
      }

      spec {
        project = "default"

        # One source block serving both kinds. Argo CD rejects a source carrying `path` and
        # `chart` at once, so each is rendered only for the element it belongs to and comes out
        # empty for the other. The guard also keeps missingkey=error happy: a key absent from an
        # element is never evaluated, because the branch it sits in is false. `target_revision`
        # needs no guard — a branch for git, a chart version for Helm.
        source {
          repo_url        = "{{ .repo_url }}"
          path            = "{{ if eq .source_kind \"git\" }}{{ .path }}{{ end }}"
          chart           = "{{ if eq .source_kind \"helm\" }}{{ .chart }}{{ end }}"
          target_revision = "{{ .revision }}"

          helm {
            values = "{{ .values }}"
          }
        }

        destination {
          server    = "https://kubernetes.default.svc"
          namespace = "{{ .namespace }}"
        }

        # cainjector rewrites `caBundle` on the validating and mutating webhook configurations
        # that cert-manager and trust-manager install. Argo CD sees that as drift and, on the
        # next sync of anything, writes the empty value back — which breaks the webhook and with
        # it every Certificate the cluster tries to issue.
        #
        # RespectIgnoreDifferences below is the half people miss: on its own, ignore_difference
        # only hides the field from the diff, and a sync triggered by any other resource still
        # pushes it. Both are needed, and each is useless against the other's failure.
        #
        # It renders for cert-pki too, where it matches no webhook and does nothing — cheaper
        # than templating it away per element.
        ignore_difference {
          group               = "admissionregistration.k8s.io"
          kind                = "ValidatingWebhookConfiguration"
          jq_path_expressions = [".webhooks[]?.clientConfig.caBundle"]
        }

        ignore_difference {
          group               = "admissionregistration.k8s.io"
          kind                = "MutatingWebhookConfiguration"
          jq_path_expressions = [".webhooks[]?.clientConfig.caBundle"]
        }

        sync_policy {
          automated {
            prune     = true
            self_heal = true
          }

          # ServerSideApply is required for cert-manager: its CRDs exceed the 262144-byte
          # last-applied-configuration annotation limit, and without it the first sync fails
          # with an error that does not obviously say so. It is set for all three rather than
          # templated per element — the attribute is a list, templating a list per element buys
          # nothing, and server-side apply is harmless on the other two.
          sync_options = [
            "CreateNamespace=true",
            "ServerSideApply=true",
            "RespectIgnoreDifferences=true",
          ]
        }
      }
    }
  }
}
