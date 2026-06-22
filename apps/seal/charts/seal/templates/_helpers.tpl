{{- define "seal.labels" -}}
app.kubernetes.io/name: {{ .name }}
app.kubernetes.io/instance: {{ .instance | default .name }}
app.kubernetes.io/part-of: seal
app.kubernetes.io/managed-by: Helm
{{- end }}
