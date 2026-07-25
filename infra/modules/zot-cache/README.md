# Zot Cache Module (Incus)

Terraform module that launches a local [Zot](https://zotregistry.dev/) OCI
registry container inside an Incus instance, used as a pull-through cache proxy
for the Talos/Incus cluster. Terraform imports the Zot image into Incus itself
(via `incus image copy` from the ghcr OCI remote, in `null_resource.import_zot`),
then instantiates the container from the resulting `zot-cache` image alias.

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
| image_alias | Alias of the Zot image in Incus (created by Terraform)        | `string` | `"zot-cache"`                             | no       |
| static_ip   | Static IPv4 address for the Zot container                     | `string` | `"10.200.10.2"`                           | no       |

## Outputs

| Name | Description          |
| ---- | -------------------- |
| port | Registry port number |

## Notes

- The Zot image is imported into Incus by Terraform (`null_resource.import_zot`,
  `incus image copy` from the ghcr OCI remote) when the `zot-cache` alias is
  absent — no external `make zot-image` step is needed.
- `terraform destroy` removes only the container instance; the cached image and
  the host cache directory survive across destroy/apply cycles.
- Image tag is pinned via the `image_ref` variable.
