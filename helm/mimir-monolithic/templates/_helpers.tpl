{{/*
Every name this chart produces is derived here and nowhere else. The module that renders it
reproduces the Service name to publish an address without asking the cluster; if you change this,
change it there too or it will publish an address nothing answers on.
*/}}

{{- define "mimir-monolithic.fullname" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "mimir-monolithic.labels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{- end -}}

{{- define "mimir-monolithic.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "mimir-monolithic.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "mimir-monolithic.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/*
Refuse at render time rather than let the process discover it. A store pointed at no bucket comes
up healthy and fails on its first write, hours later, with an error about a resource somebody else
documents creating by hand.
*/}}
{{- define "mimir-monolithic.validate" -}}
{{- if not .Values.storage.endpoint -}}
{{- fail "mimir-monolithic: .Values.storage.endpoint is required — there is no filesystem backend here, because the one this chart would fall back to is the configuration whose vendor declines to support a single process running the compactor and the store-gateway together." -}}
{{- end -}}
{{- if not .Values.storage.bucket -}}
{{- fail "mimir-monolithic: .Values.storage.bucket is required — every block, rule and alertmanager object this deployment writes goes there, and a store with no bucket starts healthy and fails on its first write." -}}
{{- end -}}
{{- if not .Values.credentialEnv -}}
{{- fail "mimir-monolithic: .Values.credentialEnv must carry the access key by reference — the configuration expands two environment variables at start-up, and with neither present the store authenticates with the text of its own placeholder." -}}
{{- end -}}
{{- end -}}
