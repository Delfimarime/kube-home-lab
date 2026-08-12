terraform {
  required_version = ">= 1.9"
  required_providers {
    argocd = {
      source  = "argoproj-labs/argocd"
      version = "~> 7.16"
    }
  }
}

# Talks to the Argo CD API, never to the Kubernetes API. Configured entirely by environment:
# ARGOCD_SERVER, ARGOCD_AUTH_TOKEN, ARGOCD_INSECURE — so no token reaches tfvars or tfstate.
provider "argocd" {
  plain_text = var.argocd_plain_text
}
