{{- define "worker.labels" -}}
app.kubernetes.io/name: worker
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: worker
app.kubernetes.io/part-of: text2pdf
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}
