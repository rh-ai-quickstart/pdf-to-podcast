{{/*
Expand the name of the chart.
*/}}
{{- define "pdf-to-podcast.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "pdf-to-podcast.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "pdf-to-podcast.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "pdf-to-podcast.labels" -}}
helm.sh/chart: {{ include "pdf-to-podcast.chart" . }}
{{ include "pdf-to-podcast.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "pdf-to-podcast.selectorLabels" -}}
app.kubernetes.io/name: {{ include "pdf-to-podcast.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Generate pod-level security context for OpenShift
*/}}
{{- define "pdf-to-podcast.podSecurityContext" -}}
{{- if .Values.openshift.enabled }}
runAsNonRoot: true
seccompProfile:
  type: {{ .Values.openshift.securityContext.pod.seccompProfile.type }}
{{- end }}
{{- end }}

{{/*
Generate container-level security context for OpenShift
*/}}
{{- define "pdf-to-podcast.containerSecurityContext" -}}
{{- if .Values.openshift.enabled }}
allowPrivilegeEscalation: {{ .Values.openshift.securityContext.container.allowPrivilegeEscalation }}
runAsNonRoot: {{ .Values.openshift.securityContext.container.runAsNonRoot }}
capabilities:
  drop:
    {{- range .Values.openshift.securityContext.container.capabilities.drop }}
    - {{ . }}
    {{- end }}
{{- end }}
{{- end }}

{{/*
Determine service type based on OpenShift mode
*/}}
{{- define "pdf-to-podcast.serviceType" -}}
{{- if .Values.openshift.enabled -}}
ClusterIP
{{- else -}}
NodePort
{{- end -}}
{{- end }}

{{/*
Generate service account name
*/}}
{{- define "pdf-to-podcast.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "pdf-to-podcast.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Internal service URLs (hostnames match docker-compose.yaml)
*/}}
{{- define "pdf-to-podcast.redisUrl" -}}
redis://redis:{{ .Values.redis.service.port }}
{{- end }}
