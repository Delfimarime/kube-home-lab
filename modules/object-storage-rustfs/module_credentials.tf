# The access key pair, when this module was given no Secret to read.
#
# `count` is what makes the two modes one input rather than a flag: given a name, this module call
# does not exist, so there is no element, no Application and nothing owned. It renders no
# resources of its own — it returns one element for the List generator below, because a module
# rendering its own ApplicationSet would give this one two.
module "credentials" {
  source = "../secret-template"
  count  = local.render_secret ? 1 : 0

  name      = local.secret_name
  keys      = local.secret_keys
  namespace = var.namespace
  chart     = var.secret_template
}
