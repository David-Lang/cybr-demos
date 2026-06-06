{{- define "giftapp-swa.name" -}}
{{- .Chart.Name }}
{{- end }}

{{- define "giftapp-swa.fullname" -}}
{{- .Chart.Name }}
{{- end }}

{{- define "giftapp-swa.labels" -}}
app: {{ include "giftapp-swa.fullname" . }}
app.kubernetes.io/name: {{ include "giftapp-swa.name" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
