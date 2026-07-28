# ADR-003: Progressive delivery with Argo Rollouts + Gateway API managedRoutes

**Status:** Accepted
**Date:** 2026-07
**Supersedes:** the original ADR-001 ("Gateway API GitOps without Argo Rollouts"),
which was contradicted by the implementation and removed.

## Context

The reference workload (`seal-api`) needs canary releases with automated quality
gates. An earlier ADR argued for plain two-Deployment + HTTPRoute weight editing
via GitOps; in practice manual weight management gives no automated analysis or
rollback, and the implementation went with Argo Rollouts instead.

## Decision

Use **Argo Rollouts** (chart 2.41.0, CRDs pinned `v1.9.0` — the `analysis` step
type requires ≥1.9.0) with **Gateway API traffic routing via `managedRoutes`**
against the Cilium `platform-gateway`.

Per workload (see `apps/seal/charts/seal/templates/rollout-api.yaml`):

- `kind: Rollout` replaces the api Deployment when `rollouts.enabled: true`
  (default **false** — charts stay usable without the controller).
- Canary strategy: `canaryService`/`stableService` +
  `trafficRouting.managedRoutes` pointing at the workload HTTPRoute
  (canary backendRef starts at `weight: 0`).
- Steps: **10% → pause 30s → analysis → 50% → pause 30s → analysis → 100%**.
- Analysis-as-code (`AnalysisTemplate`): success rate ≥ 99% and p95 latency
  ≤ 0.5s from Prometheus; `failureLimit: 1` aborts the rollout.

## Alternatives considered

- **Plain Deployments + manual HTTPRoute weights (the superseded ADR)** —
  rejected: no automated analysis, no abort/rollback, weight edits are manual
  Git commits during an incident.
- **Flagger** — rejected: another operator with its own CRD model; Argo Rollouts
  stays in the Argo ecosystem already used for GitOps (CD + Rollouts share
  tooling and UI).
- **Blue/green** — not adopted: canary with analysis covers the need; blue/green
  via managedRoutes is unverified on this stack.

## Consequences

- Delivery is a platform primitive: controller installed once (`delivery` layer,
  waves 8–9), workloads opt in via values.
- Verified by `make test-argocd-rollout` (canary ReplicaSet lifecycle,
  promotion, scale-down). The Gateway traffic-shifting path was proven in the
  PoC (`apps/seal/doc/argo-rollout-report.md`) on an earlier gateway; full e2e
  on Cilium managedRoutes is a pending test gap.
- Open hardening items: set `progressDeadlineSeconds` for automatic rollback
  timeout; align the managedRoute name with the rendered HTTPRoute name;
  parameterise the Prometheus address in AnalysisTemplates.
