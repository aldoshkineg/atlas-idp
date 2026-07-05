# Zot Cache Module

Terraform module that runs a local [Zot](https://zotregistry.dev/) container image registry as a pull-through cache proxy. Designed for kind clusters — images are cached on the host and served to cluster nodes via the shared `kind` Docker network.

## Features

- Pulls `ghcr.io/project-zot/zot` image and runs it as a Docker container
- Mounts the Zot config from the module's `zot-config.json`
- Persists cached images at a configurable host directory
- Attaches to the `kind` Docker network for node access
- On-demand sync from upstream registries (registry.k8s.io, quay.io, ghcr.io, docker.io, public.ecr.aws)

## Usage

```hcl
module "zot_cache" {
  source = "../../modules/zot-cache"

  enable       = true
  container_name = "kind-zot-registry"
  port         = 5000
  network_name = "kind"
  cache_dir    = "/var/tmp/atlas/zot_cache/zot-cache-data"
  config_dir   = "/var/tmp/atlas"

  depends_on = [module.kind_cluster]
}
```

## Inputs

| Name           | Description                     | Type     | Default                      | Required |
| -------------- | ------------------------------- | -------- | ---------------------------- | -------- |
| enable         | Enable Zot cache container      | `bool`   | `true`                       | no       |
| container_name | Name of the Zot container       | `string` | `"kind-zot-registry"`        | no       |
| port           | Port for the Zot registry       | `number` | `5000`                       | no       |
| network_name   | Docker network to attach Zot to | `string` | `"kind"`                     | no       |
| cache_dir      | Host path for Zot cache storage | `string` | `"/var/tmp/atlas/zot_cache"` | no       |
| config_dir     | Host path for Zot config file   | `string` | `"/var/tmp/atlas"`           | no       |
| image_tag      | Zot container image tag         | `string` | `"v2.1.16"`                  | no       |

## Outputs

| Name           | Description                  |
| -------------- | ---------------------------- |
| container_name | Name of the Zot container    |
| port           | Registry port number         |
| network        | Docker network name attached |

## Recreating Zot

If you need to force-recreate the Zot container (e.g., after updating the config), taint it and reapply:

```bash
# Taint the container to force recreation
terraform taint module.zot_cache.docker_container.zot[0]

# Apply to recreate
terraform apply -target=module.zot_cache
```

Or to destroy Zot while keeping the cache:

```bash
terraform destroy -target=module.zot_cache
```

The cache directory on the host (`/var/tmp/atlas/zot_cache/zot-cache-data`) is preserved across destroys.

## Notes

- Requires the `kind` Docker network to already exist — add `depends_on = [module.kind_cluster]` in the caller
- The container runs with `restart=always` so it starts automatically after a host reboot
- Uses `127.0.0.1:5000` binding for local access; nodes reach it via Docker DNS as `kind-zot-registry:5000`
- Image tag is pinned to a specific version to avoid unexpected upgrades — update `image_tag` manually
- The cache directory is created automatically by Docker on container start; no manual `mkdir` needed
- Changing the config requires tainting the container (the config file is updated on apply but the container does not auto-restart)
