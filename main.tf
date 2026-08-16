terraform {
  required_version = ">= 1.9"
  required_providers {
    argocd = {
      version = "~> 7.16"
      source  = "argoproj-labs/argocd"
    }
  }
}

provider "argocd" {}
