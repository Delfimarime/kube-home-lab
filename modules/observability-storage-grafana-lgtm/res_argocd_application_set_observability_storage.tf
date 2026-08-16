resource "argocd_application_set" "observability_storage" {
  metadata {
    name      = "observability-storage"
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

        # A List generator has no inherent order. Without these the Applications sync concurrently:
        # the collector's generated configuration would reference the scrape-target API types
        # before the CRD bundle installing them has synced, which reads as a broken chart rather
        # than as a missing dependency, and a store would start before the access key it
        # authenticates with exists.
        annotations = {
          "argocd.argoproj.io/sync-wave" = "{{ .wave }}"
        }
      }

      spec {
        project = "default"

        # One source block serving both kinds. Argo CD rejects a source carrying `path` and `chart`
        # at once, so each is rendered only for the element it belongs to and comes out empty for
        # the other. The guard also keeps missingkey=error happy: a key absent from an element is
        # never evaluated, because the branch it sits in is false. `target_revision` needs no guard
        # — a branch for git, a chart version for Helm.
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
        # operator types the real access key in. Without this, the next sync of anything would push
        # the empty values back over them and all three stores would stop authenticating at once —
        # which surfaces as every write returning 403 while every pod stays healthy.
        #
        # RespectIgnoreDifferences below is the half people miss: on its own, ignore_difference
        # only hides the field from the diff, and a sync triggered by any other resource still
        # writes it. Both are needed, and each is useless against the other's failure.
        #
        # It renders for the stores and the collector too, where it matches nothing — those charts
        # are given an existing Secret and create none — which is cheaper than templating it away
        # per element.
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

          # ServerSideApply is required for the Prometheus-operator CRDs: they exceed the
          # 262144-byte last-applied-configuration annotation limit, and without it the first sync
          # fails with an error that does not obviously say so. It is set for every element rather
          # than templated per element — the attribute is a list, templating a list per element
          # buys nothing, and server-side apply is harmless on the rest.
          #
          # Pruning reaches the credential this module rendered: removing the module block removes
          # the access key an operator typed in. Naming an existing Secret instead is how an
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
