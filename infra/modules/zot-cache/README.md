# Zot Cache Module (Incus)

Terraform module that launches a local [Zot](https://zotregistry.dev/) OCI
registry container inside an Incus instance, used as a pull-through cache proxy
for the Talos/Incus cluster. The Zot image itself is NOT managed by Terraform
(see `make zot-image`); Terraform only instantiates the container from the
already-present `zot-cache` image alias.

## Features

- Launches the `zot-cache` Incus container instance (routed NIC, static IP)
- Mounts the Zot config from the module's `zot-config.json`
- Persists cached images on a host directory (`cache_dir`)
- On-demand sync from upstream registries (registry.k8s.io, quay.io, ghcr.io, docker.io, public.ecr.aws)

## Usage

```hcl
module "zot_cache" {
  source = "../../modules/zot-cache"

  enable    = true
  network   = "atlas-br0"
  gateway   = "10.200.10.1"
  static_ip = "10.200.10.2"
  cache_dir = "/var/tmp/atlas/zot_cache/zot-cache-data"
}
```

## Inputs

| Name        | Description                                                   | Type     | Default                                   | Required |
| ----------- | ------------------------------------------------------------- | -------- | ----------------------------------------- | -------- |
| enable      | Enable Zot cache container                                    | `bool`   | `true`                                    | no       |
| port        | Zot registry listen port inside the container                 | `number` | `5000`                                    | no       |
| cache_dir   | Host path for Zot cache storage (mapped to /var/lib/registry) | `string` | `/var/tmp/atlas/zot_cache/zot-cache-data` | no       |
| network     | Incus bridge network name                                     | `string` | —                                         | yes      |
| gateway     | Bridge gateway IP (used for resolv.conf nameserver)           | `string` | —                                         | yes      |
| image_alias | Alias of the already-present Zot image in Incus               | `string` | `"zot-cache"`                             | no       |
| static_ip   | Static IPv4 address for the Zot container                     | `string` | `"10.200.10.2"`                           | no       |

## Outputs

| Name | Description          |
| ---- | -------------------- |
| port | Registry port number |

## Notes

- The Zot image must be provisioned once outside Terraform via `make zot-image`
  (copies `ghcr.io/project-zot/zot` into Incus under the alias `zot-cache`).
- `terraform destroy` removes only the container instance; the cached image and
  the host cache directory survive across destroy/apply cycles.
- Image tag is pinned at provisioning time via `make zot-image`.
