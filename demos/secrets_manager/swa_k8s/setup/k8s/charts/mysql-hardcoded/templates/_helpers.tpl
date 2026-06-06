{{- define "mysql-hardcoded.name" -}}
{{- .Chart.Name }}
{{- end }}

{{- define "mysql-hardcoded.fullname" -}}
{{- .Chart.Name }}
{{- end }}

{{- define "mysql-hardcoded.labels" -}}
app: {{ include "mysql-hardcoded.fullname" . }}
app.kubernetes.io/name: {{ include "mysql-hardcoded.name" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
