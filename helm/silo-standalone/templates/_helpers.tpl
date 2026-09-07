{{/*
Every name this chart produces is derived here and nowhere else, and a caller that needs to know one
sets it rather than reproducing the derivation. `fullnameOverride` is the whole of that: whatever is
put there is what every object is called, so something publishing an endpoint for this store states
the name it wants and reads it back from its own configuration instead of copying a formula out of
this file — which is the copy that goes stale silently and hands every client an address nothing
answers on.
*/}}

{{/*
The chart's own name, as it appears in `app.kubernetes.io/name`. Separate from the object name
because the two answer different questions: this one says *what* this is, and is the same string on
every deployment of this chart, while the object name says *which* deployment.
*/}}
{{- define "silo-standalone.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
What every object this chart renders is called. The release name unless told otherwise — this
deployment is one process and its objects are named for the release so that
`rollout restart statefulset/<release>` is the obvious command rather than one that has to be looked
up.

Deliberately *not* the `<release>-<chart>` form the usual scaffold produces: the name is also the
in-cluster hostname every client of this store is configured with, and `silo-silo-standalone` is a
hostname somebody has to be told about twice.
*/}}
{{- define "silo-standalone.fullname" -}}
{{- default .Release.Name .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "silo-standalone.labels" -}}
app.kubernetes.io/name: {{ include "silo-standalone.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- /*
  What is actually running, which is the image tag and not a version this chart states. The tag is
  the only place the running build is decided, so the label naming the version is derived from it
  rather than from a second copy that is free to disagree.

  Tags of this store are long and carry characters a label value will not hold, so the value is the
  tag reduced to what a label accepts and truncated — enough to tell two builds apart, and not an
  input anything should parse.
*/}}
app.kubernetes.io/version: {{ .Values.image.tag | replace ":" "-" | trunc 63 | trimSuffix "-" | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{- end -}}

{{/*
The subset a Service and a StatefulSet select on. It is a subset and not the whole label set because
a StatefulSet's selector is immutable: anything that may legitimately change on an upgrade — the
version above, the chart revision — must not be in here, or the upgrade is a delete and recreate,
and a delete of this StatefulSet is a delete of the only copy of the data.
*/}}
{{- define "silo-standalone.selectorLabels" -}}
app.kubernetes.io/name: {{ include "silo-standalone.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "silo-standalone.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "silo-standalone.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/*
The root credential, by reference and never by value. Both halves come out of one Secret the caller
named; this chart holds that name and two key names and learns nothing else about them.

The two environment variable names are the process's own and are fixed here rather than offered as
values, because there is nothing for a caller to decide: they exist only between this chart's pod
spec and the binary it starts, and a caller that could rename them could only get them wrong.
*/}}
{{- define "silo-standalone.credentialEnv" -}}
- name: MINIO_ROOT_USER
  valueFrom:
    secretKeyRef:
      name: {{ .Values.credentials.existingSecret.name | quote }}
      key: {{ .Values.credentials.existingSecret.accessKeyKey | quote }}
- name: MINIO_ROOT_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ .Values.credentials.existingSecret.name | quote }}
      key: {{ .Values.credentials.existingSecret.secretKeyKey | quote }}
{{- end -}}

{{/*
Refuse at render time rather than let the process discover it. Every failure below is one that
otherwise surfaces hours later as an authorization error naming nothing, a console that never
finishes loading, or a restart count.
*/}}
{{- define "silo-standalone.validate" -}}
{{- if not .Values.region -}}
{{- fail "silo-standalone: .Values.region is required — an S3 request is signed over its region, so this store and every client of it must be told the same string. Left unset the two sides pick their own defaults, agree by luck, and the day they stop agreeing the failure is an authorization error that names neither the region nor the mismatch." -}}
{{- end -}}
{{- if not .Values.credentials.existingSecret.name -}}
{{- fail "silo-standalone: .Values.credentials.existingSecret.name must name the Secret holding this store's root credential — the chart passes both halves to the process by reference and never holds a value, so with no Secret named there is nothing for the pod to read and the container fails to start." -}}
{{- end -}}
{{- if not .Values.credentials.existingSecret.accessKeyKey -}}
{{- fail "silo-standalone: .Values.credentials.existingSecret.accessKeyKey must name the key inside that Secret holding the root user. This chart never holds the value, only where to find it, so an unnamed key is a reference to nothing." -}}
{{- end -}}
{{- if not .Values.credentials.existingSecret.secretKeyKey -}}
{{- fail "silo-standalone: .Values.credentials.existingSecret.secretKeyKey must name the key inside that Secret holding the root password. This chart never holds the value, only where to find it, so an unnamed key is a reference to nothing." -}}
{{- end -}}
{{- if eq .Values.credentials.existingSecret.accessKeyKey .Values.credentials.existingSecret.secretKeyKey -}}
{{- fail "silo-standalone: .Values.credentials.existingSecret.accessKeyKey and .Values.credentials.existingSecret.secretKeyKey must differ — they are two keys in one Secret, and one name cannot hold both halves of a credential. Given the same name the user and the password are the same string, which is a store whose password is public the moment anyone reads an access log." -}}
{{- end -}}
{{- if and .Values.serverUrl .Values.browserRedirectUrl (eq .Values.serverUrl .Values.browserRedirectUrl) -}}
{{- fail "silo-standalone: .Values.serverUrl and .Values.browserRedirectUrl must not be the same address — the S3 API and the management console are two servers and this deployment tells the browser where to come back to after a login redirect. Pointed at one hostname, that redirect lands on the S3 endpoint, which answers it as a malformed bucket request, and the console never finishes loading. Give each surface a hostname of its own." -}}
{{- end -}}
{{- $limits := (.Values.resources).limits | default dict -}}
{{- if and $limits.memory (not .Values.tuning.goMemLimit) -}}
{{- fail "silo-standalone: resources.limits.memory is set and tuning.goMemLimit is empty, which is precisely the configuration that gets this pod OOM-killed. Two things inside the process read the machine's memory rather than this container's limit: it sizes its own concurrency ceiling at roughly three quarters of total RAM divided by two mebibytes per request, which under a cgroup limit is a ceiling computed from memory this pod will never be allowed to touch; and the Go runtime grows the heap until the operating system pushes back, which under a cgroup limit is the kernel killing the process rather than a collection. Set tuning.goMemLimit to about 0.85 of the memory limit — the rest is what the process needs outside the heap — or take the memory limit off." -}}
{{- end -}}
{{- end -}}

{{/*
The address this process reaches its own S3 API on. Whatever the caller stated, or the in-cluster
Service — name, namespace and the API's own port, all of which this chart already decides, so a
caller that says nothing gets an address that cannot depend on anything outside the cluster.

Deliberately not the external hostname by default. The console signs a person in by calling the
API from inside this pod, and routing that call out through whatever terminates TLS and back
requires cluster DNS to resolve an outside name, the ingress to accept traffic arriving from
behind it, and this container to trust that ingress's certificate. None of the three is implied by
the deployment working from a browser, and each fails as the same unexplained network error.
*/}}
{{- define "silo-standalone.serverUrl" -}}
{{- if .Values.serverUrl -}}
{{- .Values.serverUrl -}}
{{- else -}}
{{- printf "http://%s.%s.svc.cluster.local:%v" (include "silo-standalone.fullname" .) .Release.Namespace .Values.service.apiPort -}}
{{- end -}}
{{- end -}}
