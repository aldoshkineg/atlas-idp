resource "helm_release" "cilium" {
  name       = "cilium"
  repository = "https://helm.cilium.io/"
  chart      = "cilium"
  version    = var.cilium_chart_version
  namespace  = "kube-system"

  set {
    name  = "kubeProxyReplacement"
    value = "true"
  }

  set {
    name  = "k8sServiceHost"
    value = "${var.cluster_name}-control-plane"
  }

  set {
    name  = "k8sServicePort"
    value = "6443"
  }

  set {
    name  = "image.useDigest"
    value = "false"
  }

  set {
    name  = "image.tag"
    value = "v${var.cilium_chart_version}"
  }

  set {
    name  = "operator.image.useDigest"
    value = "false"
  }

  set {
    name  = "operator.image.tag"
    value = "v${var.cilium_chart_version}"
  }

  set {
    name  = "envoy.image.useDigest"
    value = "false"
  }

  set {
    name  = "hubble.relay.image.useDigest"
    value = "false"
  }

  set {
    name  = "certgen.image.useDigest"
    value = "false"
  }
}
