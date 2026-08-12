{{- define "postgresql.fullname" -}}
{{- default .Release.Name .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* The Secret holding the password: one this chart generates, or one already yours. */}}
{{- define "postgresql.secretName" -}}
{{- default (include "postgresql.fullname" .) .Values.auth.existingSecret }}
{{- end }}

{{- define "postgresql.selectorLabels" -}}
app.kubernetes.io/name: {{ include "postgresql.fullname" . }}
{{- end }}

{{- define "postgresql.labels" -}}
{{ include "postgresql.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/version: {{ .Values.image.tag | quote }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end }}
