terraform {
  # OpenTofu, not Terraform (ADR 019). 1.9 is the floor because a `validation` block below
  # references a second variable, which earlier versions reject.
  required_version = ">= 1.9"

  required_providers {
    argocd = {
      source  = "argoproj-labs/argocd"
      version = "~> 7.16"
    }
  }
}

# There is deliberately no `provider` block and no `backend` block here — a called module may
# declare neither. Both live in the root module, which is where the whole cluster is composed
# (ADR 020).
#
# **Nothing about reaching Argo CD is an input.** ARGOCD_SERVER, ARGOCD_AUTH_TOKEN and
# ARGOCD_INSECURE come from the operator's environment, so no credential reaches a var file or
# state, and `plain_text` — the one field with no environment variable — is the root module's.
# `var.argocd.namespace` is an input, because *where the ApplicationSet object goes* is this
# module's business rather than the connection's.
#
# This module is still written to be plannable on its own: `tofu init -backend=false` in this
# directory validates it and exercises its `validation` blocks with no cluster and no database.
