# The environment's S3 endpoint, and the one volume behind every bucket.
#
# A pass-through: everything about the store is grouped under `var.object_storage`. Nothing about
# the cluster reaches it — it emits no route, reads no issuer and has no database, so there is no
# shared contract to pass down. `git_revision` is the exception every module with a chart in this
# repository takes: it is what Argo CD reads the placeholder Secret chart at.
module "object_storage" {
  source = "./modules/object-storage-rustfs"
  argocd = {
    namespace = var.argocd.namespace
  }
  namespace       = var.object_storage.namespace
  secret_name     = var.object_storage.secret_name
  region          = var.object_storage.region
  storage         = var.object_storage.storage
  rustfs          = { chart_version = var.object_storage.chart_version }
  secret_template = merge(var.object_storage.secret_template, { revision = var.git_revision })
}
