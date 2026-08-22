{{/*
The name of the Keycloak resource, and the stem every object here is named from.
*/}}
{{- define "keycloak-instance.name" -}}
{{- default .Chart.Name .Values.name -}}
{{- end -}}

{{/*
Labels every object carries. Deliberately not the tenant label — that one belongs on the Service
the operator creates, and it is set through the resource's own serviceMonitor.labels rather than
stamped here, because this chart does not own that Service.
*/}}
{{- define "keycloak-instance.labels" -}}
app.kubernetes.io/name: {{ include "keycloak-instance.name" . }}
app.kubernetes.io/component: openid-connect
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}
