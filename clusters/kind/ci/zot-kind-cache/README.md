# Local Container Image Cache (Zot Registry Proxy)

An on-demand, pull-through cache proxy running inside Docker to optimize image retrieval and prevent rate-limiting for the local Kubernetes (`KinD`) environment.

## Key Features

- **Data Persistence:** Images are stored locally on the host (`zot-cache-data/`). Your cached images survive container updates, recreations, and purges.
- **Smart Verification:** The configuration script checks both config and storage mounts. If everything is correct, it safely restarts the container to apply changes rather than recreating it.
- **Network Sync:** Operates within the `kind` Docker network to communicate seamlessly with your Kubernetes cluster nodes.

## Usage

You can manage the cache using the root `Makefile` or by running the script directly:

### Start / Refresh Configuration

```bash
make ci-cache-up
# OR: ./setup-zot-cache.sh
```
