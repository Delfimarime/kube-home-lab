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

        # One source block serving both kinds. Argo CD rejects a source that carries `path`
        # and `chart` at once, so each is rendered only for the element it belongs to and
        # comes out empty for the other. The guard also keeps missingkey=error happy: a key
        # absent from an element is never evaluated, because the branch it sits in is false.
        # `target_revision` needs no guard — a branch for git, a chart version for Helm.
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

        # The chart generates the password on every render, because Argo CD renders with
        # `helm template` and its `lookup` of the live Secret always comes back empty. This is
        # what keeps that render from reaching the cluster: without it, every sync writes a
        # new password over the one the database is actually using and every consumer is
        # locked out. RespectIgnoreDifferences is the half people miss — on its own,
        # ignore_difference only hides the field from the diff, and a sync triggered by any
        # other resource still pushes it. It renders for CloudBeaver too, where it matches no
        # Secret and does nothing — cheaper than templating it away.
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
