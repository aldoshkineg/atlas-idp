# Apply, bootstrap, and retrieve kubeconfig for a Talos cluster.
# Config generation (talos_machine_configuration datasources) must happen
# in the caller because the incus/kind module needs those configs for VMs,
# creating a circular dependency if they were inside this module.

resource "talos_machine_configuration_apply" "controlplane" {
  count = length(var.cp_ips)

  machine_configuration_input = var.controlplane_configs[count.index]
  client_configuration        = var.client_configuration
  node                        = var.cp_ips[count.index]
  endpoint                    = var.cp_ips[count.index]
  apply_mode                  = var.apply_mode
}

resource "talos_machine_bootstrap" "this" {
  depends_on = [talos_machine_configuration_apply.controlplane]

  client_configuration = var.client_configuration
  node                 = var.cp_ips[0]
  endpoint             = var.cp_ips[0]
}

resource "talos_cluster_kubeconfig" "this" {
  depends_on = [talos_machine_bootstrap.this]

  client_configuration = var.client_configuration
  node                 = var.cp_ips[0]
  endpoint             = var.cp_ips[0]
}

resource "local_sensitive_file" "kubeconfig" {
  content  = talos_cluster_kubeconfig.this.kubeconfig_raw
  filename = "${var.files_dir}/kubeconfig"
}

resource "talos_machine_configuration_apply" "worker" {
  for_each = { for i, ip in var.worker_ips : "worker-${i + 1}" => i }

  depends_on = [talos_machine_bootstrap.this]

  machine_configuration_input = var.worker_configs[each.value]
  client_configuration        = var.client_configuration
  node                        = var.worker_ips[each.value]
  endpoint                    = var.worker_ips[each.value]
  apply_mode                  = "no_reboot"
}
