terraform {
  # An OpenTofu version, which does not read across to Terraform. 1.9 is the floor because several
  # `validation` blocks in variables.tf reference a second variable, which earlier versions reject.
  required_version = ">= 1.9"

  required_providers {
    argocd = {
      source  = "argoproj-labs/argocd"
      version = "~> 7.16"
    }
  }
}

# No `provider` block and no `backend` block: a called module may declare neither, and both live in
# the root module where the cluster is composed. ARGOCD_SERVER, ARGOCD_AUTH_TOKEN and
# ARGOCD_INSECURE come from the operator's environment, so no credential reaches a var file or
# state; `var.argocd.namespace` is an input because *where the ApplicationSet object goes* is this
# module's business rather than the connection's.
#
# `tofu init -backend=false` in this directory validates the module and exercises its `validation`
# blocks with no cluster and no object store.
