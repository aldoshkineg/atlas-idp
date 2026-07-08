> ⚠️ **OUTDATED — WORKABILITY NOT VERIFIED**
>
> This spec targets **NGINX Gateway Fabric** as the traffic-management controller.
> The current platform uses **Cilium Gateway API** (Envoy-based, Hubble enabled) instead,
> and `argo-rollouts` is already deployed via `argocd/argo-rollouts` + `argocd/argo-rollouts-crds`.
> The canary concept still applies, but every NGINX Gateway Fabric reference below must be
> revalidated/replaced with the Cilium Gateway + Envoy plugin before use.
> **Action required:** verify feasibility against the Cilium Gateway API implementation
> (see `gitops/platform/base/`) before relying on this document.

## Technical Specification for Implementing Canary Deployments with Argo Rollouts and NGINX Gateway Fabric

---

### 1. Project Objective

Implement a progressive delivery system based on **Argo Rollouts** using **NGINX Gateway Fabric** as the traffic management controller through **Kubernetes Gateway API**. The target deployment strategy is **canary**.

---

### 2. Justification

Since version 1.5, Argo Rollouts supports traffic management plugins, enabling integration with any solution implementing Kubernetes Gateway API. NGINX Gateway Fabric is the official reference implementation of Gateway API from NGINX and is fully compatible with this plugin.

---

### 3. Solution Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Kubernetes Cluster                        │
│                                                                     │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                    Argo Rollouts Controller                  │   │
│  │  ┌───────────────────────────────────────────────────────┐  │   │
│  │  │        Gateway API Plugin (loaded from ConfigMap)      │  │   │
│  │  └───────────────────────────────────────────────────────┘  │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                              │                                      │
│                              ▼                                      │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                   NGINX Gateway Fabric                       │   │
│  │              (Gateway API controller)                       │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                              │                                      │
│                              ▼                                      │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                      HTTPRoute                               │   │
│  │              (traffic weight management)                    │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                              │                                      │
│              ┌───────────────┴───────────────┐                     │
│              ▼                               ▼                     │
│  ┌─────────────────────┐     ┌─────────────────────┐             │
│  │  Stable Service     │     │  Canary Service     │             │
│  │  (old version)      │     │  (new version)      │             │
│  └─────────────────────┘     └─────────────────────┘             │
│              │                               │                     │
│              ▼                               ▼                     │
│  ┌─────────────────────┐     ┌─────────────────────┐             │
│  │  Stable Pods        │     │  Canary Pods        │             │
│  │  (replicas: X)      │     │  (replicas: Y)      │             │
│  └─────────────────────┘     └─────────────────────┘             │
└─────────────────────────────────────────────────────────────────────┘
```

**How it works:**

1. **Argo Rollouts** manages the application lifecycle and modifies weights (`weights`) in the `HTTPRoute` resource.
2. **NGINX Gateway Fabric** reads these weights and directs the corresponding percentage of traffic to the canary service.
3. Traffic splitting occurs at the controller level, allowing precise control over percentages even with a small number of pods.

---

### 4. Environment Requirements

| Component                 | Requirement                           |
| ------------------------- | ------------------------------------- |
| **Kubernetes**            | Version 1.24+ (1.28+ recommended)     |
| **Gateway API CRD**       | CRDs version `v1` or higher installed |
| **NGINX Gateway Fabric**  | Installed and configured              |
| **Argo Rollouts**         | Version 1.5+                          |
| **kubectl-argo-rollouts** | Optional, for CLI management          |

---

### 5. Implementation Steps

#### 5.1. Install Gateway API CRD

```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml
```

#### 5.2. Install NGINX Gateway Fabric

```bash
# Install via Helm
helm upgrade --install nginx-gateway-fabric oci://ghcr.io/nginxinc/charts/nginx-gateway-fabric \
  --version 1.5.0 \
  --create-namespace \
  --namespace nginx-gateway
```

#### 5.3. Configure GatewayClass and Gateway

**GatewayClass:**

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: nginx-gateway
spec:
  controllerName: gateway.nginx.org/nginx-gateway-controller
```

**Gateway:**

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: my-app-gateway
  namespace: my-app
spec:
  gatewayClassName: nginx-gateway
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      allowedRoutes:
        namespaces:
          from: Same
```

#### 5.4. Install Argo Rollouts

```bash
kubectl create namespace argo-rollouts
kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml
```

#### 5.5. Configure Gateway API Plugin

Create a `ConfigMap` to load the plugin when Argo Rollouts starts:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argo-rollouts-config
  namespace: argo-rollouts
data:
  trafficRouterPlugins: |
    - name: "argoproj-labs/gatewayAPI"
      location: "https://github.com/argoproj-labs/rollouts-plugin-trafficrouter-gatewayapi/releases/download/v0.10.0/gateway-api-plugin-linux-amd64"
```

Apply and restart the Argo Rollouts pod:

```bash
kubectl apply -f argo-rollouts-config.yaml
kubectl rollout restart deployment argo-rollouts -n argo-rollouts
```

> **Note:** The latest plugin version can be found in the [releases repository](https://github.com/argoproj-labs/rollouts-plugin-trafficrouter-gatewayapi/releases).

#### 5.6. Create Services (Stable and Canary)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-app-stable
  namespace: my-app
spec:
  selector:
    app: my-app
    version: stable
  ports:
    - port: 80
      targetPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: my-app-canary
  namespace: my-app
spec:
  selector:
    app: my-app
    version: canary
  ports:
    - port: 80
      targetPort: 8080
```

#### 5.7. Create HTTPRoute

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: my-app-route
  namespace: my-app
spec:
  parentRefs:
    - name: my-app-gateway
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: my-app-stable
          port: 80
          weight: 100
        - name: my-app-canary
          port: 80
          weight: 0
```

> **Note:** Initial weights are set in HTTPRoute, but during canary deployment, Argo Rollouts will modify them automatically.

#### 5.8. Create Rollout Resource

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: my-app
  namespace: my-app
spec:
  replicas: 10
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
        version: stable
    spec:
      containers:
        - name: my-app
          image: my-app:stable
          ports:
            - containerPort: 8080
  strategy:
    canary:
      maxSurge: "25%"
      maxUnavailable: 0
      steps:
        - setWeight: 10
        - pause: { duration: 60s }
        - setWeight: 25
        - pause: { duration: 60s }
        - setWeight: 50
        - pause: { duration: 60s }
        - setWeight: 100
      trafficRouting:
        plugins:
          argoproj-labs/gatewayAPI:
            httpRoutes:
              - name: my-app-route
```

#### 5.9. Start Canary Deployment

Update the image in Rollout:

```bash
kubectl argo rollouts set image my-app my-app=my-app:v2.0 -n my-app
```

Monitor status:

```bash
kubectl argo rollouts get rollout my-app -n my-app --watch
```

---

### 6. Acceptance Criteria

| #   | Criterion                                                                                                       |
| --- | --------------------------------------------------------------------------------------------------------------- |
| 1   | When updating the image, canary pods of the new version are created                                             |
| 2   | Weights in HTTPRoute are automatically adjusted according to the canary strategy steps (10% → 25% → 50% → 100%) |
| 3   | Traffic is distributed between stable and canary services proportionally to the set weights                     |
| 4   | When reaching 100% weight, the canary version becomes stable                                                    |
| 5   | In case of failure (analysis/pause failure), rollback is possible                                               |

---

### 7. Limitations and Risks

| Limitation                 | Description                                                                                |
| -------------------------- | ------------------------------------------------------------------------------------------ |
| **Canary Only**            | The Gateway API plugin **does not support** Blue/Green strategy                            |
| **Version Dependency**     | The plugin requires Gateway API `v1` and above; versions `0.x` are not supported           |
| **Plugin Loading**         | On each Argo Rollouts restart, the plugin is reloaded; stable access to GitHub is required |
| **Backward Compatibility** | When updating Argo Rollouts, plugin version compatibility must be checked                  |
| **Single Gateway**         | NGINX Gateway Fabric supports only one Gateway resource                                    |

---

### 8. Work Plan

| Step                                          | Duration   | Responsible      |
| --------------------------------------------- | ---------- | ---------------- |
| 1. Install Gateway API CRD                    | 0.5 days   | DevOps           |
| 2. Install and configure NGINX Gateway Fabric | 1 day      | DevOps           |
| 3. Install Argo Rollouts                      | 0.5 days   | DevOps           |
| 4. Configure Gateway API plugin               | 0.5 days   | DevOps           |
| 5. Create test application and Rollout        | 1 day      | Developer/DevOps |
| 6. Test canary deployment                     | 1 day      | QA/DevOps        |
| 7. Documentation and handover                 | 0.5 days   | DevOps           |
| **Total**                                     | **5 days** |                  |

---

### 9. Information Verification

| Statement                                                               | Source | Status       |
| ----------------------------------------------------------------------- | ------ | ------------ |
| Argo Rollouts supports traffic management plugins since version 1.5     |        | ✅ Confirmed |
| The Gateway API plugin works with any solution implementing Gateway API |        | ✅ Confirmed |
| NGINX Gateway Fabric is a Gateway API implementation                    |        | ✅ Confirmed |
| The plugin does not support Blue/Green                                  |        | ✅ Confirmed |
| The plugin requires Gateway API version v1 and above                    |        | ✅ Confirmed |
| The plugin is configured via argo-rollouts-config ConfigMap             |        | ✅ Confirmed |
| NGINX Gateway Fabric supports weighted routing                          |        | ✅ Confirmed |

---

### 10. Useful Links

- [Argo Rollouts Gateway API Plugin (GitHub)](https://github.com/argoproj-labs/rollouts-plugin-trafficrouter-gatewayapi)
- [Plugin Documentation](https://rollouts-plugin-trafficrouter-gatewayapi.readthedocs.io)
- [NGINX Gateway Fabric (GitHub)](https://github.com/nginx/nginx-gateway-fabric)
- [List of Gateway API Implementations](https://gateway-api.sigs.k8s.io/implementations/)
- [Plugin Usage Examples](https://github.com/argoproj-labs/rollouts-plugin-trafficrouter-gatewayapi/tree/main/examples)
