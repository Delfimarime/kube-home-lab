# The composition. Every module this cluster ships is called from here, in one state, planned
# and applied together (ADR 020).

terraform {
  # 1.9 is the floor: a `validation` block in the cert-manager module references a second
  # variable, which earlier versions reject.
  required_version = ">= 1.9"

  required_providers {
    argocd = {
      source  = "argoproj-labs/argocd"
      version = "~> 7.16"
    }
  }

  # Empty on purpose. A backend block takes no variables and no interpolation, so which
  # environment's state this is gets decided at `init` time:
  #
  #   tofu init -backend-config=<file>
  #
  # `PG_CONN_STR` carries the address and the credential, so nothing about where state lives
  # reaches git (ADR 012).
  backend "pg" {}
}
