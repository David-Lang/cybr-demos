{{- define "giftapp-hardcoded.name" -}}
{{- .Chart.Name }}
{{- end }}

{{- define "giftapp-hardcoded.fullname" -}}
{{- .Chart.Name }}
{{- end }}

{{- define "giftapp-hardcoded.labels" -}}
app: {{ include "giftapp-hardcoded.fullname" . }}
app.kubernetes.io/name: {{ include "giftapp-hardcoded.name" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
