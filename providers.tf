# The one provider, configured once. Modules declare `required_providers` and inherit this
# configuration; none of them declares a provider block of its own.
#
# Everything the provider can take from the environment does — ARGOCD_SERVER, ARGOCD_AUTH_TOKEN,
# ARGOCD_INSECURE — so no credential reaches a var file or state. `plain_text` is the one field
# with no environment variable, which is why it is the only one written here.
#
# That is also what makes the environment a property of the shell rather than of the tree: the
# provider addresses whichever cluster ARGOCD_SERVER names (ADR 020).
provider "argocd" {
  plain_text = var.argocd.plain_text
}
