resource "argocd_application_set" "object_storage" {
  metadata {
    name      = "object-storage"
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

        # A List generator has no inherent order. Without these the Secret and the workload sync
        # concurrently, and a pod that starts before its credential exists is a crash loop that
        # resolves itself — but looks exactly like a wrong access key, which does not.
        annotations = {
          "argocd.argoproj.io/sync-wave" = "{{ .wave }}"
        }
      }

      spec {
        project = "default"

        # One source block serving both kinds. Argo CD rejects a source carrying `path` and
        # `chart` at once, so each is rendered only for the element it belongs to and comes out
        # empty for the other. The guard also keeps missingkey=error happy: a key absent from an
        # element is never evaluated, because the branch it sits in is false.
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

        # The placeholder Secret is rendered with its keys present and their values empty; an
        # operator types the real ones in. Without this, the next sync of anything would push the
        # empty values back over them and the store would stop authenticating.
        #
        # RespectIgnoreDifferences below is the half people miss: on its own, ignore_difference
        # only hides the field from the diff, and a sync triggered by any other resource still
        # writes it. Both are needed, and each is useless against the other's failure.
        #
        # It renders for the workload's Application too, where it matches nothing — that chart is
        # given an existing Secret and creates none — which is cheaper than templating it away per
        # element.
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
          # the access key an operator typed in. Naming an existing Secret instead is how an
          # environment keeps it outside that lifecycle.
          sync_options = [
            "CreateNamespace=true",
            "RespectIgnoreDifferences=true",
          ]
        }
      }
    }
  }
}
