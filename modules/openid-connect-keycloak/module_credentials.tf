# The two credentials Keycloak reads, each rendered here only when it was given no Secret to read.
#
# `count` is what makes the two modes one input rather than a flag: given a name, that module call
# does not exist, so there is no element, no Application and nothing owned. Neither renders
# resources of its own — each returns one element for the List generator, because a module
# rendering its own ApplicationSet would give this one three.
#
# They are two objects rather than one because they are filled at two different moments by two
# different people: the database credential comes from whoever owns the PostgreSQL, and the
# administrator's password is chosen by whoever will use it. One Secret holding both would have to
# be revisited every time either changed.

module "database_credentials" {
  source = "../secret-template"
  count  = local.render_db_secret ? 1 : 0

  name           = local.db_secret_name
  keys           = local.db_secret_keys
  namespace      = var.namespace
  git_repository = var.git_repository
}

# Rendered whether or not anything else is configured: this account is the way in when the realm's
# configuration is wrong, so the one state where it matters most is the one where nothing else
# would have created it. Left empty it grants nobody anything, which is the correct state until
# somebody fills it.
#
# Its keys are `username` and `password`, stated in locals rather than taken from inputs, because
# the operator reads them by fixed name.
module "bootstrap_admin_credentials" {
  source = "../secret-template"
  count  = local.render_admin_secret ? 1 : 0

  name           = local.admin_secret_name
  keys           = local.admin_secret_keys
  namespace      = var.namespace
  git_repository = var.git_repository
}
