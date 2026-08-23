{{/*
The name of the Keycloak resource, and the stem every object here is named from.
*/}}
{{- define "keycloak-instance.name" -}}
{{- default .Chart.Name .Values.name -}}
{{- end -}}

{{/*
The identity half of the label set: which workload this is and which release rendered it. Separate
from the block below because these are the labels a selector would be written against, and those
must not move when a chart version or a server build does.
*/}}
{{- define "keycloak-instance.selectorLabels" -}}
app.kubernetes.io/name: {{ include "keycloak-instance.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Labels every object carries. Deliberately not the tenant label — that one belongs on the Service
the operator creates, and it is set through the resource's own serviceMonitor.labels rather than
stamped here, because this chart does not own that Service.

`app.kubernetes.io/version` is the *server's* version and is written only when one is known. The
ordinary case is that it is not: leaving `image` empty is what lets the operator run the Keycloak
its own release was built against, and this chart declares no appVersion for the same reason. When
an environment pins an image, its tag is the version and the label says so rather than staying
silent about a build somebody chose deliberately.
*/}}
{{- define "keycloak-instance.labels" -}}
{{- include "keycloak-instance.selectorLabels" . }}
app.kubernetes.io/component: openid-connect
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{- $ref := splitList "@" (default "" .Values.image) | first }}
{{- $tag := regexFind ":[^:/]+$" $ref | trimPrefix ":" }}
{{- with default .Chart.AppVersion $tag }}
app.kubernetes.io/version: {{ . | trunc 63 | trimSuffix "-" | quote }}
{{- end }}
{{- end -}}
