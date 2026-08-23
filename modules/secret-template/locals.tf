locals {
  # The chart this module renders, published from this repository's own `helm/` tree rather than
  # owned by this module — so its values schema is the chart's and a second consumer is allowed.
  # A constant rather than an input: the only correct value is this one, and a caller able to
  # change it could only ever point an Application at a path that does not exist.
  chart_path = "helm/secret-template"
}
