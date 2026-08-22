# The object stores' access keys, one placeholder per distinct Secret this module was asked to
# create.
#
# A Secret is namespaced, so an object store module's own copy is not readable from here and the
# credential has to exist a second time, in this namespace. It must be the same value, and nothing
# checks that it is: the symptom of getting it wrong is every write returning 403 while the stores
# look perfectly healthy.
#
# **Usually there is exactly one, and there can be more.** Stores left on the shared storage block
# resolve to one name and get one Secret between them; a store carrying its own block gets one of
# its own, because a different endpoint is a different credential and inheriting this cluster's
# would be the quiet failure the whole replacing-not-merging rule exists to prevent.
#
# `for_each` over the resolved names is what makes those two cases one expression: a store told to
# read an existing Secret contributes no key here, so it produces no element, no Application and
# nothing owned. This renders no resources of its own — it returns elements for the List generator,
# because a module rendering its own ApplicationSet would give this one several.
module "credentials" {
  source   = "../secret-template"
  for_each = local.rendered_secrets

  name           = each.key
  keys           = each.value
  namespace      = var.namespace
  git_repository = var.git_repository
}
