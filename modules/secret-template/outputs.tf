# One element for the caller's List generator, in the shape every module here already uses:
# `source_kind` selects which of `path` and `chart` the Application template renders, and both
# keys are present because a List generator's elements must agree on their keys.
#
# `chart` is empty because this is read from git rather than from a chart registry.
output "element" {
  value = {
    name        = var.name
    source_kind = "git"
    repo_url    = var.git_repository.url
    chart       = ""
    path        = local.chart_path
    revision    = var.git_repository.revision
    namespace   = var.namespace
    wave        = var.wave
    values = yamlencode({
      name = var.name
      keys = var.keys
    })
  }
  description = "The List-generator element rendering this Secret. Concatenate it into the caller's own charts."
}

# The name back out again, so a caller that resolved it from `coalesce` does not have to hold the
# same expression twice.
output "name" {
  value       = var.name
  description = "The Secret's name."
}
