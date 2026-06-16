# Cilium Helm settings
locals {
  cilium_default_settings = [
    {
      name  = "kubeProxyReplacement"
      value = "true"
    },
    {
      name  = "k8sServiceHost"
      value = "${var.cluster_name}-control-plane"
    },
    {
      name  = "k8sServicePort"
      value = "6443"
    },
    {
      name  = "image.useDigest"
      value = "false"
    },
    {
      name  = "image.tag"
      value = "v${var.cilium_chart_version}"
    },
    {
      name  = "operator.image.useDigest"
      value = "false"
    },
    {
      name  = "operator.image.tag"
      value = "v${var.cilium_chart_version}"
    },
    {
      name  = "envoy.image.useDigest"
      value = "false"
    },
    {
      name  = "hubble.relay.image.useDigest"
      value = "false"
    },
    {
      name  = "certgen.image.useDigest"
      value = "false"
    },
  ]

  cilium_settings = concat(local.cilium_default_settings, var.cilium_settings)
}

resource "helm_release" "cilium" {
  name       = "cilium"
  repository = "https://helm.cilium.io/"
  chart      = "cilium"
  version    = var.cilium_chart_version
  namespace  = "kube-system"

  dynamic "set" {
    iterator = cilium_setting
    for_each = local.cilium_settings

    content {
      name  = cilium_setting.value.name
      value = cilium_setting.value.value
    }
  }
}
