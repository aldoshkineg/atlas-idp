# Cilium Helm settings
locals {
  cilium_talos_settings = var.talos ? [
    { name = "rollOutCiliumPods", value = "true", type = "auto" },
    { name = "cni.chainingMode", value = "none" },
    { name = "identityAllocationMode", value = "crd" },
    { name = "cgroup.autoMount.enabled", value = "false", type = "auto" },
    { name = "cgroup.hostRoot", value = "/sys/fs/cgroup" },
    { name = "k8sServiceHost", value = "localhost" },
    { name = "k8sServicePort", value = "7445" },
    { name = "securityContext.capabilities.ciliumAgent", value = "{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}", type = "auto" },
    { name = "securityContext.capabilities.cleanCiliumState", value = "{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}", type = "auto" },
  ] : []

  cilium_k8s_service = var.talos ? [] : [
    {
      name  = "k8sServiceHost"
      value = var.k8s_service_host != "" ? var.k8s_service_host : "${var.cluster_name}-control-plane"
    },
    {
      name  = "k8sServicePort"
      value = var.k8s_service_port
    },
  ]

  cilium_default_settings = concat(local.cilium_talos_settings, concat(local.cilium_k8s_service, [
    {
      name  = "kubeProxyReplacement"
      value = "true"
    },
    {
      name  = "image.useDigest"
      value = "false"
      type  = "auto"
    },
    {
      name  = "image.tag"
      value = "v${var.cilium_chart_version}"
    },
    {
      name  = "operator.image.useDigest"
      value = "false"
      type  = "auto"
    },
    {
      name  = "operator.image.tag"
      value = "v${var.cilium_chart_version}"
    },
    {
      name  = "envoy.image.useDigest"
      value = "false"
      type  = "auto"
    },
    {
      name  = "envoy.image.tag"
      value = var.envoy_image_tag
    },
    {
      name  = "hubble.relay.image.useDigest"
      value = "false"
      type  = "auto"
    },
    {
      name  = "hubble.relay.image.tag"
      value = "v${var.cilium_chart_version}"
    },
    {
      name  = "certgen.image.useDigest"
      value = "false"
      type  = "auto"
    },
    {
      name  = "certgen.image.tag"
      value = var.certgen_image_tag
    },
    {
      name  = "hubble.ui.backend.image.useDigest"
      value = "false"
      type  = "auto"
    },
    {
      name  = "hubble.ui.backend.image.tag"
      value = var.hubble_ui_backend_tag
    },
    {
      name  = "hubble.ui.frontend.image.useDigest"
      value = "false"
      type  = "auto"
    },
    {
      name  = "hubble.ui.frontend.image.tag"
      value = var.hubble_ui_frontend_tag
    },
  ]))

  cilium_settings = concat(local.cilium_default_settings, var.cilium_settings)
}

resource "helm_release" "cilium" {
  name       = "cilium"
  repository = "https://helm.cilium.io/"
  chart      = "cilium"
  version    = var.cilium_chart_version
  namespace  = "kube-system"
  timeout    = 600

  dynamic "set" {
    iterator = s
    for_each = local.cilium_settings

    content {
      name  = s.value.name
      value = s.value.value
      type  = lookup(s.value, "type", "string")
    }
  }
}
