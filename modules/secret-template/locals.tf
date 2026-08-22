locals {
  # Where this module's chart sits inside this repository. A constant rather than an input: the
  # only correct value is this one, and a caller able to change it could only ever point an
  # Application at a path that does not exist.
  chart_path = "modules/secret-template/helm/secret-template"
}
