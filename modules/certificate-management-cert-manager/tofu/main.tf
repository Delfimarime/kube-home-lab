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

# There is deliberately no `provider` block and no `backend` block here.
#
# `root.hcl` generates both for every unit that includes it, so that the provider and the
# backend read their target from the same `env.hcl` and cannot disagree about which environment
# is being addressed (ADR 012). Declaring either here would collide with the generated file.
#
# **What the generated provider reads.** Everything the provider can take from the environment
# comes from there and never from a variable: ARGOCD_SERVER, ARGOCD_AUTH_TOKEN, ARGOCD_INSECURE.
# That keeps the token out of tfvars and out of state. `plain_text` has no environment variable,
# so it — and only it — is a module input with a default. A field that cannot come from the
# environment is the only reason to add one.
#
# Driving this module directly, before the scaffolding exists, means writing that provider block
# by hand; see prompt/certificate-management-cert-manager.plan.md.
