{{/*
Every name this chart produces is derived here and nowhere else. outputs.tf reproduces these
formulas so a consumer can be told a Secret name without asking the cluster; if you change one,
change it there too or the module will publish a name that does not exist.
*/}}

{{- define "cert-pki.fullname" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "cert-pki.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{- end -}}

{{/* The self-signed Issuer that bootstraps an authority. Takes (dict "root" $ "name" <key>). */}}
{{- define "cert-pki.selfSignedName" -}}
{{- printf "%s-%s-selfsigned" (include "cert-pki.fullname" .root) .name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* The authority itself: its Certificate, its Secret and its ClusterIssuer all share this. */}}
{{- define "cert-pki.caName" -}}
{{- printf "%s-%s-ca" (include "cert-pki.fullname" .root) .name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* An entry's server certificate, and the Secret holding it. */}}
{{- define "cert-pki.certName" -}}
{{- printf "%s-%s-tls" (include "cert-pki.fullname" .root) .name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* An entry's client certificate. Only mtls entries have one. */}}
{{- define "cert-pki.clientCertName" -}}
{{- printf "%s-%s-client" (include "cert-pki.fullname" .root) .name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
