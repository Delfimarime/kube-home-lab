{{/*
The names and labels the two objects this chart adds are built from. Everything else in a release
of this chart comes from the chart it wraps and is named by that chart's own helpers — nothing here
reaches into them, which is what keeps this a wrapper rather than a fork.

The one place that rule bends is the pod selector, which by its nature has to match labels the
wrapped chart writes. It is a value rather than a helper for exactly that reason: a formula copied
from upstream goes stale silently, and a value can be checked.
*/}}

{{/*
This chart's own name. Not the wrapped chart's: an object rendered here is this chart's doing, and
a label claiming otherwise would send a reader looking for it upstream.
*/}}
{{- define "ory-keto.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
The stem every object here is named from, and the same formula the other charts in this repository
use. The release name alone, deliberately: the wrapped chart names its Services from the release
too, so a stem that added the chart name would put this chart's objects under a prefix nothing else
in the release shares.
*/}}
{{- define "ory-keto.fullname" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
The identity half of the label set. Separate from the block below because these are the labels a
selector would be written against, and those must not move when a chart version does.
*/}}
{{- define "ory-keto.selectorLabels" -}}
app.kubernetes.io/name: {{ include "ory-keto.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/*
Every label the added objects carry.

`app.kubernetes.io/version` is conditional because it is the *application's* version, and this
chart declares no appVersion: the application here is the store the wrapped chart runs, whose
version is pinned in `Chart.yaml`'s dependency and would be a third place to edit on an upgrade —
one more chance to bump two of three and ship a change that looks applied and is not.
*/}}
{{- define "ory-keto.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{ include "ory-keto.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
The labels identifying the *store's* pods — the ones the wrapped chart creates and this chart's
NetworkPolicy has to select. `podSelector` from values, plus the release, so two releases in one
namespace cannot select each other's pods.

Refuses to render when `keto.nameOverride` is set and the selector was not moved with it. That is
the one edit whose failure mode is silent and open: the wrapped chart relabels its pods, this
policy then selects nothing, and a policy applying to no pod leaves the write port reachable by
everything while every object in the release stays green.
*/}}
{{- define "ory-keto.storePodLabels" -}}
{{- $override := dig "nameOverride" "" (.Values.keto | default dict) -}}
{{- if $override -}}
{{- $named := index .Values.podSelector "app.kubernetes.io/name" | default "" -}}
{{- if ne $named $override -}}
{{- fail (printf "ory-keto: keto.nameOverride is %q but podSelector's app.kubernetes.io/name is %q. The NetworkPolicy selects the store's pods by that label, so leaving them different produces a policy that matches no pod and protects nothing — while everything reconciles healthy. Set podSelector to match, or drop the override." $override $named) -}}
{{- end -}}
{{- end -}}
{{- range $k, $v := .Values.podSelector }}
{{ $k }}: {{ $v | quote }}
{{- end }}
app.kubernetes.io/instance: {{ .Release.Name | quote }}
{{- end -}}
