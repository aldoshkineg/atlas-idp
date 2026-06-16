resource "kind_cluster" "default" {
  count = var.create_cluster ? 1 : 0

  name            = var.cluster_name
  kubeconfig_path = pathexpand(var.kubeconfig_path)
  node_image      = var.kubernetes_version != "" ? "kindest/node:${var.kubernetes_version}" : null

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    # Enable containerd registry lookup in certs.d.
    containerd_config_patches = var.enable_cache ? [
      <<-TOML
      [plugins."io.containerd.grpc.v1.cri".registry]
        config_path = "/etc/containerd/certs.d"
      TOML
    ] : null

    networking {
      disable_default_cni = var.disable_default_cni
      kube_proxy_mode     = var.disable_default_cni ? "none" : "iptables"
    }

    # Control-plane node.
    node {
      role = "control-plane"

      kubeadm_config_patches = var.ingress_ready ? [
        <<-EOF
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
        EOF
      ] : null

      dynamic "extra_port_mappings" {
        for_each = var.extra_port_mappings
        content {
          container_port = extra_port_mappings.value.container_port
          host_port      = extra_port_mappings.value.host_port
          protocol       = upper(extra_port_mappings.value.protocol)
        }
      }
    }

    # Worker nodes.
    dynamic "node" {
      for_each = range(var.worker_node_count)
      content {
        role = "worker"
      }
    }
  }

  provisioner "local-exec" {
    command = <<-EOT
if [ "${var.enable_cache}" = "true" ]; then

  for node in $(docker ps -q --filter "label=io.x-k8s.kind.cluster=${var.cluster_name}"); do
    docker exec $node rm -rf /etc/containerd/certs.d/_default/hosts.toml
    docker exec $node mkdir -p /etc/containerd/certs.d/_default
    docker exec -i $node sh -c "cat > /etc/containerd/certs.d/_default/hosts.toml" <<EOF
server = "${var.cache_registry_server}"

[host."${var.cache_host_url}"]
  capabilities = ${jsonencode(var.cache_host_capabilities)}
EOF

    docker exec $node systemctl restart containerd
  done
fi
EOT
  }
}
