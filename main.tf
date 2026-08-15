terraform {
  required_version = ">= 1.9"
  required_providers {
    argocd = {
      version = "~> 7.16"
      source  = "argoproj-labs/argocd"
    }
  }
}

provider "argocd" {
  plain_text = var.argocd.plain_text
}
