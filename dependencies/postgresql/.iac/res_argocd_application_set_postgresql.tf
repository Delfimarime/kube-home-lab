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

        # A git source, not a chart repository: the chart lives in this repository, which is
        # also why `path` replaces `chart` and the revision is a branch rather than a version.
        source {
          repo_url        = "{{ .repo_url }}"
          path            = "{{ .path }}"
          target_revision = "{{ .revision }}"

          helm {
            values = "{{ .values }}"
          }
        }

        destination {
          server    = "https://kubernetes.default.svc"
          namespace = "{{ .namespace }}"
        }

        # The chart generates the password on every render, because Argo CD renders with
        # `helm template` and its `lookup` of the live Secret always comes back empty. This is
        # what keeps that render from reaching the cluster: without it, every sync writes a
        # new password over the one the database is actually using and every consumer is
        # locked out. RespectIgnoreDifferences is the half people miss — on its own,
        # ignore_difference only hides the field from the diff, and a sync triggered by any
        # other resource still pushes it.
        ignore_difference {
          kind          = "Secret"
          name          = "{{ .name }}"
          json_pointers = ["/data/password"]
        }

        sync_policy {
          automated {
            prune     = true
            self_heal = true
          }

          sync_options = ["CreateNamespace=true", "RespectIgnoreDifferences=true"]
        }
      }
    }
  }
}
