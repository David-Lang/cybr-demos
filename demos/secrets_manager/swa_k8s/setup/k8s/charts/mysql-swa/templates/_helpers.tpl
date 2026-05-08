{{- define "mysql-swa.name" -}}
{{- .Chart.Name }}
{{- end }}

{{- define "mysql-swa.fullname" -}}
{{- .Chart.Name }}
{{- end }}

{{- define "mysql-swa.labels" -}}
app: {{ include "mysql-swa.fullname" . }}
app.kubernetes.io/name: {{ include "mysql-swa.name" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
