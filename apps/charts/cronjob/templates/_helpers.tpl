{{- define "cronjob.labels" -}}
app.kubernetes.io/name: cronjob
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: cronjob
app.kubernetes.io/part-of: text2pdf
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}
