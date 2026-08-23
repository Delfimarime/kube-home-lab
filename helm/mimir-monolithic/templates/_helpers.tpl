{{/*
Every name this chart produces is derived here and nowhere else, and a caller that needs to know one
sets it rather than reproducing the derivation. `fullnameOverride` is the whole of that: whatever is
put there is what every object is called, so something publishing an address for this deployment
states the name it wants and reads it back from its own configuration instead of copying a formula
out of this file — which is the copy that goes stale silently and publishes an address nothing
answers on.
*/}}

{{/*
The chart's own name, as it appears in `app.kubernetes.io/name`. Separate from the object name
because the two answer different questions: this one says *what* this is, and is the same string on
every deployment of this chart, while the object name says *which* deployment.
*/}}
{{- define "mimir-monolithic.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
What every object this chart renders is called. The release name unless told otherwise — this
deployment is one process and its objects are named for the release so that
`rollout restart statefulset/<release>` is the obvious command rather than one that has to be looked
up.

Deliberately *not* the `<release>-<chart>` form the usual scaffold produces: the name is also the
in-cluster hostname every reader of this store is configured with, and `mimir-mimir-monolithic` is a
hostname somebody has to be told about twice.
*/}}
{{- define "mimir-monolithic.fullname" -}}
{{- default .Release.Name .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "mimir-monolithic.labels" -}}
app.kubernetes.io/name: {{ include "mimir-monolithic.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- /*
  What is actually running, which is the image tag and not the chart's `appVersion`. The two are the
  same until somebody pins a different tag, and at that moment the label naming the version is the
  one nobody thinks to change — so it is derived from the tag that was pinned instead.
*/}}
app.kubernetes.io/version: {{ default .Chart.AppVersion .Values.image.tag | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{- end -}}

{{/*
The subset a Service and a StatefulSet select on. It is a subset and not the whole label set because
a StatefulSet's selector is immutable: anything that may legitimately change on an upgrade — the
version above, the chart revision — must not be in here, or the upgrade is a delete and recreate.
*/}}
{{- define "mimir-monolithic.selectorLabels" -}}
app.kubernetes.io/name: {{ include "mimir-monolithic.name" . }}
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
The two environment variables the access key reaches the process as. They are this chart's own
names and nothing outside needs to know them: a caller names a Secret and the two keys inside it,
and the entries below and the placeholders in the configuration are built from that here, in one
place, so the three cannot drift out of agreement.

Fixed rather than configurable because there is nothing for a caller to decide — they exist only
between this chart's pod spec and this chart's configuration file, both of which are written here.
*/}}
{{- define "mimir-monolithic.accessKeyVar" -}}OBJECT_STORAGE_ACCESS_KEY{{- end -}}
{{- define "mimir-monolithic.secretKeyVar" -}}OBJECT_STORAGE_SECRET_KEY{{- end -}}

{{/*
The literal text the configuration file carries in place of each half of the access key. The process
expands it at start-up, which is why it is started with environment expansion switched on; a value
here would be a credential sitting in a ConfigMap and in the Application spec that renders it.
*/}}
{{- define "mimir-monolithic.accessKeyPlaceholder" -}}
{{- printf "${%s}" (include "mimir-monolithic.accessKeyVar" .) -}}
{{- end -}}

{{- define "mimir-monolithic.secretKeyPlaceholder" -}}
{{- printf "${%s}" (include "mimir-monolithic.secretKeyVar" .) -}}
{{- end -}}

{{/*
The credential, by reference and never by value. Both halves come out of one Secret the caller
named; this chart holds that name and two key names and learns nothing else about them.
*/}}
{{- define "mimir-monolithic.credentialEnv" -}}
- name: {{ include "mimir-monolithic.accessKeyVar" . }}
  valueFrom:
    secretKeyRef:
      name: {{ .Values.storage.existingSecret.name | quote }}
      key: {{ .Values.storage.existingSecret.accessKeyKey | quote }}
- name: {{ include "mimir-monolithic.secretKeyVar" . }}
  valueFrom:
    secretKeyRef:
      name: {{ .Values.storage.existingSecret.name | quote }}
      key: {{ .Values.storage.existingSecret.secretKeyKey | quote }}
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
{{- if not .Values.storage.existingSecret.name -}}
{{- fail "mimir-monolithic: .Values.storage.existingSecret.name must name the Secret holding the object store's access key — the configuration expands two environment variables at start-up, and with neither present the store authenticates with the text of its own placeholder." -}}
{{- end -}}
{{- if not .Values.storage.existingSecret.accessKeyKey -}}
{{- fail "mimir-monolithic: .Values.storage.existingSecret.accessKeyKey must name the key inside that Secret holding the access key id. This chart never holds the value, only where to find it, so an unnamed key is a reference to nothing." -}}
{{- end -}}
{{- if not .Values.storage.existingSecret.secretKeyKey -}}
{{- fail "mimir-monolithic: .Values.storage.existingSecret.secretKeyKey must name the key inside that Secret holding the secret access key. This chart never holds the value, only where to find it, so an unnamed key is a reference to nothing." -}}
{{- end -}}
{{- if eq .Values.storage.existingSecret.accessKeyKey .Values.storage.existingSecret.secretKeyKey -}}
{{- fail "mimir-monolithic: .Values.storage.existingSecret.accessKeyKey and .Values.storage.existingSecret.secretKeyKey must differ — they are two keys in one Secret, and one name cannot hold both halves of an access key pair. Given the same name, both environment variables carry the same half and every write is refused with a signature mismatch." -}}
{{- end -}}
{{- end -}}
