resource "argocd_application_set" "identity" {
  metadata {
    name      = "openid-connect"
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

        # A List generator has no inherent order. Without these the operator's CRDs may not exist
        # when the instance declares a `Keycloak` against them — a failure that reads as a broken
        # chart rather than as a race.
        annotations = {
          "argocd.argoproj.io/sync-wave" = "{{ .wave }}"
        }
      }

      spec {
        project = "default"

        # `path` is rendered unconditionally, unlike the other modules here: every source in this
        # module is read from git — two charts of this repository's and upstream's manifests — so
        # there is no chart-registry element whose `chart` would have to be guarded against it.
        #
        # **`values` still needs its guard, and for a reason that is easy to miss.** An element's
        # empty-string entries are dropped rather than carried, so the operator — which passes no
        # values, having no chart to pass them to — arrives with no `values` key at all. Under
        # `missingkey=error` that is a render failure for the whole ApplicationSet, not an empty
        # string. The branch is false for that element, so the key is never evaluated.
        source {
          repo_url        = "{{ .repo_url }}"
          path            = "{{ .path }}"
          target_revision = "{{ .revision }}"

          helm {
            values = "{{ if ne .source_kind \"kustomize\" }}{{ .values }}{{ end }}"
          }
        }

        destination {
          server    = "https://kubernetes.default.svc"
          namespace = "{{ .namespace }}"
        }

        # A placeholder Secret is rendered with its keys present and their values empty; an
        # operator types the real ones in. The content of `.data` is therefore owned by a person
        # rather than by the chart, and without this the next sync of anything would push the
        # empty values back over what they typed — Keycloak would stop reaching its database and
        # the break-glass account would stop admitting anyone.
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

          # ServerSideApply is required rather than precautionary here: the `Keycloak` CRD alone
          # is half a megabyte, which is twice the 262144-byte last-applied-configuration
          # annotation limit, and without it the operator's first sync fails with an error that
          # does not obviously say so.
          #
          # Pruning reaches every credential this module rendered: removing the module block
          # removes the values an operator typed in, and with them the way into the database
          # holding the realm. Naming existing Secrets instead is how an environment keeps them
          # outside that lifecycle.
          sync_options = [
            "CreateNamespace=true",
            "ServerSideApply=true",
            "RespectIgnoreDifferences=true",
          ]
        }
      }
    }

    # The operator is not a chart, and a `List` generator has one template for every element.
    #
    # Two things have to happen for that element only. **The `helm` block has to go**, because
    # Argo CD types a source by which of `helm` and `kustomize` is *present* rather than by
    # whether it is empty — an element carrying `helm: {values: ""}` is a Helm source, and a
    # kustomization underneath it is a chart Argo CD cannot find. **And the namespace has to be
    # overridden**, because upstream's kustomization stamps `keycloak` onto every namespaced
    # resource through a NamespaceTransformer; a destination namespace does not override a
    # namespace a manifest already states, so without this the operator lands somewhere other
    # than where its instance is.
    #
    # `templatePatch` is applied as a Kubernetes strategic merge patch, in which a null deletes a
    # key — which is what makes both possible in one place.
    template_patch = <<-EOT
      {{- if eq .source_kind "kustomize" }}
      spec:
        source:
          helm: null
          kustomize:
            namespace: {{ .namespace }}
      {{- end }}
    EOT
  }
}
