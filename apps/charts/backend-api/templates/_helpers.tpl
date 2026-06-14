{{- define "backend-api.labels" -}}
app.kubernetes.io/name: backend-api
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: backend-api
app.kubernetes.io/part-of: text2pdf
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}
