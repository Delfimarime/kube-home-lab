module "resource_authorization" {
  source = "./modules/resource-authorization-ory-keto"
  count  = var.resource_authorization == null ? 0 : 1
  argocd = {
    namespace = var.argocd.namespace
  }
  namespace            = var.resource_authorization.namespace
  database_secret_name = var.resource_authorization.database_secret_name

  # **The file is read here and the structure is passed through**, because only these two lines can
  # be in both places at once: a path is relative to this directory, so `file()` has to run where
  # the path was written, while the structured form is the module's own input and is validated
  # there.
  #
  # Both null ships the chart's default — one subject namespace and nothing else, a store that runs
  # and authorizes nobody. That is what an environment wants before it has an application whose
  # objects are worth describing.
  model = var.resource_authorization.model == null ? null : {
    content    = try(var.resource_authorization.model.file, null) == null ? null : file("${path.module}/${var.resource_authorization.model.file}")
    namespaces = try(var.resource_authorization.model.namespaces, null)
  }

  # **The applications that write tuples, named here because nothing else knows them.** They are
  # workloads this repository does not deploy — it provisions platform capabilities, not the things
  # that consume them — so their selectors are stated by the environment rather than read from a
  # module output.
  #
  # Each entry is one caller. An application that grants access to a resource it owns writes the
  # tuple itself, and reads `check` on the open read port when it serves a request.
  write_access_from = var.resource_authorization.write_access_from

  metrics        = local.metrics.resource_authorization
  git_repository = var.git_repository
}
