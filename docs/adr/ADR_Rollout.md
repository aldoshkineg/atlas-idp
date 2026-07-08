# Gateway API Native Canary Deployment Model (without Argo Rollouts)

## Status

Accepted

> [!WARNING] > **Implementation diverged from this decision.** This ADR selected
> "Gateway API + GitOps **without Argo Rollouts**" (two Deployments + HTTPRoute
> weights via Git commits). The platform actually deployed **Argo Rollouts**
> (`gitops/platform/delivery/argo-rollouts.yaml`) with traffic routing via
> **Cilium Gateway API `managedRoutes`** (e.g.
> `apps/seal/charts/seal/templates/rollout-api.yaml`). The decision record below
> is kept for history; the **Verification** section reflects the implemented
> design. The ADR should be superseded/updated to match reality.

## Context

The task is to implement:

- safe canary releases
- gradual traffic shifting
- rollback capability
- observability (logs/metrics)
- GitOps integration (Argo CD)
- use of Gateway API (Gateway API)
- NGINX Gateway Fabric as the data plane

## Solution Options

### Option A — Argo Rollouts

Using Argo Rollouts as a progressive delivery controller.

#### Architecture

```text
Git → Argo CD → Rollout → ReplicaSets → Service → Gateway
```

#### Mechanism

- Rollout creates ReplicaSets
- Manages traffic weights and rollout steps
- Executes pause/analysis phases
- Can automatically increase traffic
- Supports automatic rollback

#### Requirements

- Integration with a traffic router (Istio / NGINX Ingress / Traefik, etc.)
- Or fallback to replica-based canary

### Option B — Gateway API + GitOps (Selected Approach)

```text
Git → Argo CD → Deployments + HTTPRoute → Gateway → Traffic
```

#### Mechanism

- Two Deployments (stable/canary)
- One Service (or minimal abstraction layer)
- Traffic is controlled via HTTPRoute weights
- Weight changes are done via Git commits

## Comparison

### Traffic Management

| Criteria                  | Argo Rollouts | Gateway API GitOps |
| ------------------------- | ------------- | ------------------ |
| Automated weight shifting | ✔            | ✖                 |
| Manual control            | ✔            | ✔                 |
| Transparency              | Medium        | High               |
| Vendor lock-in            | Medium        | Low                |

### Release Automation

| Criteria               | Argo Rollouts | Gateway API GitOps |
| ---------------------- | ------------- | ------------------ |
| Pause/steps            | ✔            | ✖                 |
| Metrics analysis       | ✔            | ✖                 |
| Auto rollback          | ✔            | ✖                 |
| Git as source of truth | Partial       | Full               |

### Architectural Complexity

| Criteria                    | Argo Rollouts | Gateway API GitOps |
| --------------------------- | ------------- | ------------------ |
| Number of components        | High          | Low                |
| Additional controllers/CRDs | Yes           | No                 |
| Debugging complexity        | Higher        | Lower              |

### Gateway API Compatibility

- Rollouts:

  - partial / limited integration
  - depends on supported traffic routers

- Gateway API GitOps:
  - native model
  - HTTPRoute is the source of truth

## Key Architectural Difference

### Argo Rollouts (control-plane driven)

```text
Controller manages release
Controller adjusts traffic
```

### Gateway API GitOps (declarative-driven)

```text
Git defines traffic state
Argo CD applies desired state
```

## Justification for Choosing Gateway API GitOps

### Minimal Complexity Principle

The system already includes:

- Argo CD
- Gateway API
- NGINX Gateway Fabric

Adding Rollouts would:

- increase number of controllers
- duplicate traffic management logic

### Single Source of Truth

Gateway API approach ensures:

- HTTPRoute is the only source of truth for traffic
- no hidden control logic in a rollout controller
- fully reproducible state via Git

### Release Transparency

Each release step:

```text
commit:
  weight: 10 → 30 → 50 → 100
```

is:

- audit-friendly
- reviewable
- rollbackable via git revert

### Operational Simplicity

There is no:

- rollout controller state machine
- internal step engine
- analysis templates

Instead there are:

- Kubernetes objects
- Git commits
- Argo CD synchronization

## Final Architecture

### Runtime

```text
Gateway API (NGINX Gateway Fabric)
```

### Delivery

```text
Argo CD (GitOps)
```

### Workload Model

```text
Deployment (stable)
Deployment (canary)
Service (single entrypoint)
HTTPRoute (traffic splitting)
```

## Canary Flow

### Step 1 — Deploy canary

```yaml
stable: 100%
canary: 0–10%
```

### Step 2 — Observation

- logs
- metrics (Prometheus / OpenTelemetry)

### Step 3 — Progressive traffic shift

```text
90/10 → 50/50 → 0/100
```

### Step 4 — Promotion

- canary becomes stable
- old version is removed

## Final Decision Statement

### Selected approach:

> Use Gateway API + GitOps via Argo CD as the primary canary deployment mechanism, without Argo Rollouts.

### Rationale:

- reduced number of control-plane components
- fully declarative Git-based workflow
- native compatibility with Gateway API
- no need for an additional rollout controller
- transparent and reproducible release lifecycle
- sufficient functionality for canary deployments via traffic splitting and observation

## Conclusion

- Argo Rollouts is a release orchestration controller
- Gateway API + GitOps is a declarative traffic management model

In this architecture, the second approach is preferred due to its simplicity, transparency, and native compatibility with the existing stack (Argo CD + Gateway API + NGINX Gateway Fabric).

---

## Verification (Runbook)

> [!WARNING]
> The acceptance-criteria checklist and commands below were adapted from the
> deleted `todo/TODO_ROLLOUT.md` (which targeted NGINX Gateway Fabric + a plugin
> ConfigMap — **not** the current stack). They have **NOT been validated on a
> live cluster** and require verification.

### Implemented model (actual)

- **Controller:** Argo Rollouts (`gitops/platform/delivery/`).
- **Traffic routing:** Cilium Gateway API (Envoy) via
  `strategy.canary.trafficRouting.managedRoutes` → HTTPRoute name.
- **Services:** `canaryService` / `stableService` for canary/stable.
- **Steps:** `strategy.canary.steps` — stepwise weight shift with pauses/analysis.

### Acceptance Criteria

| #   | Criterion                                                                 | How to verify                                                                          |
| --- | ------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| 1   | On image update, canary pods of the new version are created               | `kubectl get pods -l app.kubernetes.io/name=seal-api` — new-version ReplicaSet visible |
| 2   | HTTPRoute weights auto-adjust per strategy steps (10% → 25% → 50% → 100%) | Rollout status: `kubectl argo rollouts get rollout seal-api`                           |
| 3   | Traffic is split between stable/canary proportionally to weights          | Inspect request distribution (Prometheus metrics / logs)                               |
| 4   | At 100% weight the canary becomes stable; old version is removed          | Rollout reaches `Healthy`/`Completed`; old ReplicaSet scaled to zero                   |
| 5   | On failure (analysis/pause failure) rollback is possible                  | Abort with an invalid tag → `kubectl argo rollouts abort` / `undo`                     |

> [!NOTE]
> Resource names/namespaces (e.g. `seal-api`, `<ns>`, `<seal-route>`) **must be
> confirmed** against the actual cluster before relying on this checklist.

### Commands (example: seal-api)

```bash
# 1. Log in to Argo CD
bash tools/argocd-login.sh

# 2. Start the canary (new image)
kubectl argo rollouts set image seal-api seal-api=<registry>/seal-api:<new-tag> -n <ns>

# 3. Watch steps (weights, pauses, analysis)
kubectl argo rollouts get rollout seal-api -n <ns> --watch

# 4. Inspect the HTTPRoute (managed route weights)
kubectl get httproute <seal-route> -n <ns> -o yaml

# 5. Rollback on failure
kubectl argo rollouts abort seal-api -n <ns>
# or
kubectl argo rollouts undo seal-api -n <ns>
```

### Limitations (current for managedRoutes)

> [!WARNING]
> Carried over from the original (NGINX-centric) spec and **require
> re-validation** for Cilium + managedRoutes:

- Blue/Green strategy of Argo Rollouts is **not supported** via the Gateway API
  plugin/managedRoutes (only canary / traffic-shifting).
- The Rollout depends on Gateway API `v1` and a correctly configured Cilium Gateway.
- When upgrading Argo Rollouts, verify `managedRoutes` compatibility with the new version.
