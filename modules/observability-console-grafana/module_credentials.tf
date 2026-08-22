# The three credentials Grafana reads, each rendered here only when it was given no Secret to read.
#
# `count` is what makes the two modes one input rather than a flag: given a name, that module call
# does not exist, so there is no element, no Application and nothing owned. None of them renders
# resources of its own — each returns one element for the List generator, because a module
# rendering its own ApplicationSet would give this one four.
#
# They are three objects rather than one because they are filled at three different moments by
# three different facts: the database credential comes from whoever owns the PostgreSQL, the
# administrator's password is chosen by whoever will use it, and the client secret is shown once by
# the issuer's console. One Secret holding all three would have to be revisited every time any of
# them changed.

module "database_credentials" {
  source = "../secret-template"
  count  = local.render_database_secret ? 1 : 0

  name           = local.database_secret_name
  keys           = local.database_secret_keys
  namespace      = var.namespace
  git_repository = var.git_repository
}

# Rendered whether or not an issuer is wired: this account is the way in when the issuer is down,
# so the one configuration where it matters most is the one where nothing else would have created
# it. Left empty it grants nobody anything, which is the correct state until somebody fills it.
module "admin_credentials" {
  source = "../secret-template"
  count  = local.render_admin_secret ? 1 : 0

  name           = local.admin_secret_name
  keys           = local.admin_secret_keys
  namespace      = var.namespace
  git_repository = var.git_repository
}

# Only when an issuer is wired at all. With no `oidc` there is no client, so a Secret for its
# secret would be an empty object nothing ever reads.
module "oidc_credentials" {
  source = "../secret-template"
  count  = local.render_oidc_secret ? 1 : 0

  name           = local.oidc_secret_name
  keys           = local.oidc_secret_keys
  namespace      = var.namespace
  git_repository = var.git_repository
}
