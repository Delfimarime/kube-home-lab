# The one credential the store reads, rendered here only when it was given no Secret to read.
#
# `count` is what makes the two modes one input rather than a flag: given a name, this module call
# does not exist, so there is no element, no Application and nothing owned. It renders no resources
# of its own — it returns one element for the List generator, because a module rendering its own
# ApplicationSet would give this one two.
#
# One key rather than two. The store takes a single `DSN`, so the username, the password, the host,
# the database and the sslmode are all inside one string an operator types — which is why this
# module has no `host_port` input to disagree with it.

module "database_credentials" {
  source = "../secret-template"
  count  = local.render_db_secret ? 1 : 0

  name           = local.db_secret_name
  keys           = local.db_secret_keys
  namespace      = var.namespace
  wave           = "0"
  git_repository = var.git_repository
}
