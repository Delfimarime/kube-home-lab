resource "argocd_application_set" "console" {
  metadata {
    name      = "observability-console"
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

        # A List generator has no inherent order. Without these the Secrets and the workload sync
        # concurrently, and Grafana reaching PostgreSQL with no credential is a crash loop that
        # resolves itself — but looks exactly like a wrong password, which does not.
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

        # A placeholder Secret is rendered with its keys present and their values empty; an
        # operator types the real ones in. The content of `.data` is therefore owned by a person
        # rather than by the chart, and without this the next sync of anything would push the empty
        # values back over what they typed — Grafana would stop reaching its database, stop
        # accepting the administrator's password, and stop completing the token exchange.
        #
        # RespectIgnoreDifferences below is the half people miss: on its own, ignore_difference
        # only hides the field from the diff, and a sync triggered by any other resource still
        # writes it. Both are needed, and each is useless against the other's failure.
        #
        # It renders for Grafana's own Application too, where it matches nothing — that chart is
        # given a name for every Secret it reads and creates none — which is cheaper than
        # templating it away per element.
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

          # Pruning reaches every credential this module rendered: removing the module block
          # removes the values an operator typed in, and with them Grafana's way into the one
          # database holding state nothing else can regenerate. Naming existing Secrets instead is
          # how an environment keeps them outside that lifecycle.
          sync_options = [
            "CreateNamespace=true",
            "RespectIgnoreDifferences=true",
          ]
        }
      }
    }
  }
}
