locals {
  object_storage_services = {
    for name, s in var.object_storage.services : name => {
      port     = s.port
      hostname = s.hostname
      gateway = s.hostname == null ? null : {
        name         = s.gateway.name != null ? s.gateway.name : var.gateway.name
        namespace    = s.gateway.namespace != null ? s.gateway.namespace : var.gateway.namespace
        section_name = s.gateway.section_name != null ? s.gateway.section_name : var.gateway.section_name
      }
    }
  }
}
