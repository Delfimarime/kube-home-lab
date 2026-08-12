resource "argocd_application_set" "postgresql" {
  metadata {
    name      = "postgresql"
    namespace = var.argocd_namespace
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
      }

      spec {
        project = "default"

        source {
          repo_url        = local.chart_repository
          chart           = "{{ .chart }}"
          target_revision = "{{ .version }}"

          helm {
            values = "{{ .values }}"
          }
        }

        destination {
          server    = "https://kubernetes.default.svc"
          namespace = "{{ .namespace }}"
        }

        sync_policy {
          automated {
            prune     = true
            self_heal = true
          }

          # ServerSideApply because the CNPG CRDs exceed the annotation limit client-side apply
          # uses. Harmless for the cluster chart, so it is set once for both elements.
          sync_options = ["CreateNamespace=true", "ServerSideApply=true"]

          # The cluster chart cannot sync until the operator's CRDs exist. Retrying is the
          # ordering mechanism — Argo CD has no dependency between Applications.
          retry {
            limit = "5"
            backoff {
              duration     = "15s"
              factor       = "2"
              max_duration = "5m"
            }
          }
        }
      }
    }
  }
}
