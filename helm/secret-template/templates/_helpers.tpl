{{/*
The names and labels every object here carries, derived in one place. This chart renders a single
Secret whose *name* is an input — that is the whole interface — so nothing below ever renames the
object; what is derived here is the label set, which is how a reader of the cluster tells a
placeholder credential apart from one somebody created by hand.
*/}}

{{/*
The chart's own name, and the stem `fullname` builds on. There is no nameOverride value on purpose:
this chart's identity is fixed and its object's name is `.Values.name`, so an override would be a
second name for the same thing.
*/}}
{{- define "secret-template.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
The release-scoped stem, matching the other charts in this repository so a reader moving between
them finds the same formula. **It is not the Secret's name** — that is `.Values.name`, because the
workload reading the Secret was told a name before this chart existed. It is here as the stem for
anything else this chart is ever given to render.
*/}}
{{- define "secret-template.fullname" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
The identity half of the label set: which chart this is and which release rendered it. Separate
from the block below because these are the labels that would go into a selector, and a selector's
labels must not change when a chart or an application version does.
*/}}
{{- define "secret-template.selectorLabels" -}}
app.kubernetes.io/name: {{ include "secret-template.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Every label the Secret carries. `managed-by` was already here and is what tells an operator the
empty values are Helm's doing rather than a failed edit; the rest is the standard set, so this
object answers the same questions as everything else this repository renders.

`app.kubernetes.io/version` is conditional because it is the *application's* version and this chart
declares no appVersion — there is no application behind an empty Secret. It renders the day one is
declared rather than being a field that lies in the meantime.
*/}}
{{- define "secret-template.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{ include "secret-template.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
