# Local Container Image Cache (Zot Registry Proxy)

This setup provisions a local **Zot Registry** running as an on-demand, pull-through cache proxy inside Docker. It optimizes container image retrieval for the local Kubernetes (`KinD`) environment by proxying and caching images from upstream registries (Docker Hub, GCR, Quay).

---

## Why Use It?

* **High Performance:** Drastically reduces cluster spin-up and pod deployment times by pulling images from a local cache on subsequent runs.
* **Rate-Limit Protection:** Prevents hitting Docker Hub anonymous pull limits during intensive local development and iterative testing.
* **Offline-Friendly:** Once images are cached, you can wipe and recreate your KinD cluster completely offline.

---

## How It Works

1. **Network Sync:** The setup script ensures a dedicated Docker network (`kind`) exists so the Zot proxy and Kubernetes nodes can communicate seamlessly using container hostnames.
2. **Configuration Guard:** Validates the presence of `zot-config.json` before launch to prevent Docker from incorrectly mounting a missing file as an empty directory.
3. **Idempotent Deployment:** Inspects existing containers. If an old or misconfigured Zot container is found, it safely destroys and recreates it.
4. **Terraform Integration:** Once active, the KinD Terraform module injects a `hosts.toml` configuration into the cluster nodes, routing all node image pull requests through this Zot container (`http://kind-zot-registry:5000`) transparently.

---

## Quick Start

### 1. Spin up the Cache Proxy
Run the setup script from the directory containing your `zot-config.json`:
```bash
chmod +x setup-zot-cache.sh
./setup-zot-cache.sh
```
