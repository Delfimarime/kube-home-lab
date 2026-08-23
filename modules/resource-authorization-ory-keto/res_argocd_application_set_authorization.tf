resource "argocd_application_set" "resource_authorization" {
  metadata {
    name      = "resource-authorization"
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

        # A List generator has no inherent order. Without these the store can be created before
        # the Secret it reads its connection string from — which is not a broken chart, it is a
        # pod that crash-loops on a `DSN` that does not exist yet.
        annotations = {
          "argocd.argoproj.io/sync-wave" = "{{ .wave }}"
        }
      }

      spec {
        project = "default"

        # Both sources here are read from git — this repository's own charts — so `path` is
        # rendered unconditionally and there is no chart-registry element whose `chart` would have
        # to be guarded against it.
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

        # The placeholder Secret is rendered with its key present and its value empty; an operator
        # types the connection string in. The content of `.data` is therefore owned by a person
        # rather than by the chart, and without this the next sync of anything would push the
        # empty value back over it — the store would lose its database and every authorization
        # question in the cluster would start failing.
        #
        # RespectIgnoreDifferences below is the half people miss: on its own, ignore_difference
        # only hides the field from the diff, and a sync triggered by any other resource still
        # writes it. Both are needed, and each is useless against the other's failure.
        ignore_difference {
          group               = ""
          kind                = "Secret"
          jq_path_expressions = [".data"]
        }

        sync_policy {
          automated {
            prune     = true
            self_heal = true
          }

          # Pruning reaches the credential this module rendered: removing the module block removes
          # the connection string an operator typed in. Naming an existing Secret instead is how an
          # environment keeps it outside that lifecycle.
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
