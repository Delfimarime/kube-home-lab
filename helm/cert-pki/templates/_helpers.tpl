{{/*
Every name this chart produces is derived here, and every one of them can be stated outright in
values instead. That second half is the point: a consumer who has to know a Secret name before the
cluster exists should *set* the name rather than reproduce the formula, because a formula copied
into another artifact is a second definition of the same name with nothing keeping the two in
step. Set the name, publish the name you set, and the chart's defaults stop being load-bearing.

The defaults below are still what an operator running `helm install` by hand gets, and they are
what makes every object in a release recognisably one release's.
*/}}

{{/*
The chart's own name, overridable so two releases of it can be told apart by label as well as by
instance — the ordinary Helm convention, and the reason `app.kubernetes.io/name` is not simply
.Chart.Name.
*/}}
{{- define "cert-pki.name" -}}
{{- .Values.nameOverride | default .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
The prefix every generated name is built from. It is the release name, which for this chart is
whatever Argo CD called the Application — so a consumer that wants a stable prefix regardless of
how the release was named sets fullnameOverride and stops depending on that coincidence.
*/}}
{{- define "cert-pki.fullname" -}}
{{- .Values.fullnameOverride | default .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "cert-pki.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
app.kubernetes.io/name: {{ include "cert-pki.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- with .Chart.AppVersion }}
app.kubernetes.io/version: {{ . | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
The self-signed Issuer that bootstraps an authority. Takes (dict "root" $ "name" <key>).

Not overridable, and deliberately: nothing outside this chart ever references it. It exists for
the few seconds it takes to sign the authority's own certificate and is never named again.
*/}}
{{- define "cert-pki.selfSignedName" -}}
{{- printf "%s-%s-selfsigned" (include "cert-pki.fullname" .root) .name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
The authority itself: its Certificate, its Secret and its ClusterIssuer all share this name.
`authorities.<name>.secretName` states it outright. Takes (dict "root" $ "name" <key>).
*/}}
{{- define "cert-pki.caName" -}}
{{- $authority := index .root.Values.authorities .name | default dict -}}
{{- if $authority.secretName -}}
{{- $authority.secretName -}}
{{- else -}}
{{- printf "%s-%s-ca" (include "cert-pki.fullname" .root) .name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
An entry's server certificate, and the Secret holding it. `certificates.<name>.server.secretName`
states it outright. Takes (dict "root" $ "name" <key>).
*/}}
{{- define "cert-pki.certName" -}}
{{- $server := (index .root.Values.certificates .name | default dict).server | default dict -}}
{{- if $server.secretName -}}
{{- $server.secretName -}}
{{- else -}}
{{- printf "%s-%s-tls" (include "cert-pki.fullname" .root) .name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
An entry's client certificate. Only entries carrying a `client` block have one, and
`certificates.<name>.client.secretName` states its name outright. Takes (dict "root" $ "name" <key>).
*/}}
{{- define "cert-pki.clientCertName" -}}
{{- $client := (index .root.Values.certificates .name | default dict).client | default dict -}}
{{- if $client.secretName -}}
{{- $client.secretName -}}
{{- else -}}
{{- printf "%s-%s-client" (include "cert-pki.fullname" .root) .name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
