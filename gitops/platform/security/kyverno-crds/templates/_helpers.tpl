{{/* vim: set filetype=mustache: */}}

{{- define "kyverno.crds.labels" -}}
{{- template "kyverno.labels.merge" (list
  (include "kyverno.labels.common" .)
  (include "kyverno.crds.matchLabels" .)
  (toYaml .Values.customLabels)
) -}}
{{- end -}}

{{- define "kyverno.crds.matchLabels" -}}
{{- template "kyverno.labels.merge" (list
  (include "kyverno.matchLabels.common" .)
  (include "kyverno.labels.component" "crds")
) -}}
{{- end -}}

{{/* --- vendored parent helpers so the crds subchart renders standalone --- */}}
{{/* vim: set filetype=mustache: */}}

{{- define "kyverno.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "kyverno.fullname" -}}
{{- if .Values.fullnameOverride -}}
  {{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
  {{- $name := default .Chart.Name .Values.nameOverride -}}
  {{- if contains $name .Release.Name -}}
    {{- .Release.Name | trunc 63 | trimSuffix "-" -}}
  {{- else -}}
    {{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
  {{- end -}}
{{- end -}}
{{- end -}}

{{- define "kyverno.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "kyverno.namespace" -}}
{{ default .Release.Namespace .Values.namespaceOverride }}
{{- end -}}
{{/* vim: set filetype=mustache: */}}

{{- define "kyverno.labels.merge" -}}
{{- $labels := dict -}}
{{- range . -}}
  {{- $labels = merge $labels (fromYaml .) -}}
{{- end -}}
{{- with $labels -}}
  {{- toYaml $labels -}}
{{- end -}}
{{- end -}}

{{- define "kyverno.labels.helm" -}}
{{- if not .Values.templating.enabled -}}
helm.sh/chart: {{ template "kyverno.chart" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
{{- end -}}

{{- define "kyverno.labels.version" -}}
app.kubernetes.io/version: {{ template "kyverno.chartVersion" . }}
{{- end -}}

{{- define "kyverno.labels.common" -}}
{{- template "kyverno.labels.merge" (list
  (include "kyverno.labels.helm" .)
  (include "kyverno.labels.version" .)
  (toYaml .Values.customLabels)
) -}}
{{- end -}}

{{- define "kyverno.matchLabels.common" -}}
app.kubernetes.io/part-of: {{ template "kyverno.fullname" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "kyverno.labels.component" -}}
app.kubernetes.io/component: {{ . }}
{{- end -}}

{{- define "kyverno.labels.name" -}}
app.kubernetes.io/name: {{ . }}
{{- end -}}
{{/* vim: set filetype=mustache: */}}

{{- define "kyverno.chartVersion" -}}
{{- if .Values.templating.enabled -}}
  {{- required "templating.version is required when templating.enabled is true" .Values.templating.version | replace "+" "_" -}}
{{- else -}}
  {{- .Chart.Version | replace "+" "_" -}}
{{- end -}}
{{- end -}}

{{- define "kyverno.features.flags" -}}
{{- $flags := list -}}
{{- with .admissionReports -}}
  {{- $flags = append $flags (print "--admissionReports=" .enabled) -}}
  {{- with .backPressureThreshold -}}
    {{- $flags = append $flags (print "--maxAdmissionReports=" .) -}}
  {{- end -}}
{{- end -}}
{{- with .aggregateReports -}}
  {{- $flags = append $flags (print "--aggregateReports=" .enabled) -}}
{{- end -}}
{{- with .policyReports -}}
  {{- $flags = append $flags (print "--policyReports=" .enabled) -}}
{{- end -}}
{{- with .validatingAdmissionPolicyReports -}}
  {{- $flags = append $flags (print "--validatingAdmissionPolicyReports=" .enabled) -}}
{{- end -}}
{{- with .autoUpdateWebhooks -}}
  {{- $flags = append $flags (print "--autoUpdateWebhooks=" .enabled) -}}
{{- end -}}
{{- with .backgroundScan -}}
  {{- $flags = append $flags (print "--backgroundScan=" .enabled) -}}
  {{- $flags = append $flags (print "--backgroundScanWorkers=" .backgroundScanWorkers) -}}
  {{- $flags = append $flags (print "--backgroundScanInterval=" .backgroundScanInterval) -}}
  {{- $flags = append $flags (print "--skipResourceFilters=" .skipResourceFilters) -}}
{{- end -}}
{{- with .configMapCaching -}}
  {{- $flags = append $flags (print "--enableConfigMapCaching=" .enabled) -}}
{{- end -}}
{{- with .deferredLoading -}}
  {{- $flags = append $flags (print "--enableDeferredLoading=" .enabled) -}}
{{- end -}}
{{- with .dumpPayload -}}
  {{- $flags = append $flags (print "--dumpPayload=" .enabled) -}}
{{- end -}}
{{- with .forceFailurePolicyIgnore -}}
  {{- $flags = append $flags (print "--forceFailurePolicyIgnore=" .enabled) -}}
{{- end -}}
{{- with .generateValidatingAdmissionPolicy -}}
  {{- $flags = append $flags (print "--generateValidatingAdmissionPolicy=" .enabled) -}}
{{- end -}}
{{- with .dumpPatches -}}
  {{- $flags = append $flags (print "--dumpPatches=" .enabled) -}}
{{- end -}}
{{- with .globalContext -}}
  {{- $flags = append $flags (print "--maxAPICallResponseLength=" (int .maxApiCallResponseLength)) -}}
{{- end -}}
{{- with .logging -}}
  {{- $flags = append $flags (print "--loggingFormat=" .format) -}}
  {{- $flags = append $flags (print "--v=" (join "," .verbosity)) -}}
{{- end -}}
{{- with .omitEvents -}}
  {{- with .eventTypes -}}
    {{- $flags = append $flags (print "--omitEvents=" (join "," .)) -}}
  {{- end -}}
{{- end -}}
{{- with .policyExceptions -}}
  {{- $flags = append $flags (print "--enablePolicyException=" .enabled) -}}
  {{- with .namespace -}}
    {{- $flags = append $flags (print "--exceptionNamespace=" .) -}}
  {{- end -}}
{{- end -}}
{{- with .protectManagedResources -}}
  {{- $flags = append $flags (print "--protectManagedResources=" .enabled) -}}
{{- end -}}
{{- with .registryClient -}}
  {{- $flags = append $flags (print "--allowInsecureRegistry=" .allowInsecure) -}}
  {{- $flags = append $flags (print "--registryCredentialHelpers=" (join "," .credentialHelpers)) -}}
{{- end -}}
{{- with .ttlController -}}
  {{- $flags = append $flags (print "--ttlReconciliationInterval=" .reconciliationInterval) -}}
{{- end -}}
{{- with .tuf -}}
  {{- with .enabled -}}
    {{- $flags = append $flags (print "--enableTuf=" .) -}}
  {{- end -}}
  {{- with .mirror -}}
    {{- $flags = append $flags (print "--tufMirror=" .) -}}
  {{- end -}}
  {{- with .root -}}
    {{- $flags = append $flags (print "--tufRoot=" .) -}}
  {{- end -}}
  {{- with .rootRaw -}}
    {{- $flags = append $flags (print "--tufRootRaw=" .) -}}
  {{- end -}}
{{- end -}}
{{- with .reporting -}}
  {{- $reportingConfig := list -}}
  {{- with .validate -}}
    {{- $reportingConfig = append $reportingConfig "validate" -}}
  {{- end -}}
  {{- with .mutate -}}
    {{- $reportingConfig = append $reportingConfig "mutate" -}}
  {{- end -}}
  {{- with .mutateExisting -}}
    {{- $reportingConfig = append $reportingConfig "mutateExisting" -}}
  {{- end -}}
  {{- with .imageVerify -}}
    {{- $reportingConfig = append $reportingConfig "imageVerify" -}}
  {{- end -}}
  {{- with .generate -}}
    {{- $reportingConfig = append $reportingConfig "generate" -}}
  {{- end -}}
  {{- $flags = append $flags (print "--enableReporting=" (join "," $reportingConfig)) -}}
{{- end -}}
{{- with $flags -}}
  {{- toYaml . -}}
{{- end -}}
{{- end -}}
