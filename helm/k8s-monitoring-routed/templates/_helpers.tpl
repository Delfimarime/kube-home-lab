{{/*
The names and labels the one object this chart adds is built from. Everything else in a release of
this chart comes from the chart it wraps and is named by that chart's own helpers — nothing here
reaches into them, which is what keeps this a wrapper rather than a fork.
*/}}

{{/*
This chart's own name. Not the wrapped chart's: an object rendered here is this chart's doing, and
a label claiming otherwise would send a reader looking for it upstream.
*/}}
{{- define "k8s-monitoring-routed.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
The stem every object here is named from, and the same formula the other charts in this repository
use. The release name alone, deliberately: the wrapped chart names its Services from the release
too, so a stem that added the chart name would put this chart's objects under a prefix nothing else
in the release shares.
*/}}
{{- define "k8s-monitoring-routed.fullname" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
The identity half of the label set. Separate from the block below because these are the labels a
selector would be written against, and those must not move when a chart version does.
*/}}
{{- define "k8s-monitoring-routed.selectorLabels" -}}
app.kubernetes.io/name: {{ include "k8s-monitoring-routed.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Every label the route carries.

`app.kubernetes.io/version` is conditional because it is the *application's* version, and this
chart declares no appVersion: the application here is the collector the wrapped chart runs, whose
version is pinned in `Chart.yaml`'s dependency and would be a third place to edit on an upgrade -
one more chance to bump two of three and ship a change that looks applied and is not.
*/}}
{{- define "k8s-monitoring-routed.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{ include "k8s-monitoring-routed.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
