# ShopNow Deployment Strategy

## Objectives

Deploy repeatably with immutable artifacts, small blast radius, observable
verification, and a tested rollback. Application builds occur in the ShopNow
pipeline; platform reconciliation and Kubernetes rollout occur through the
infrastructure pipeline.

## Artifact strategy

1. Check out a reviewed commit.
2. Restore dependencies from committed lockfiles with `npm ci`.
3. Run tests, builds, dependency checks and container scanning.
4. Build frontend, admin and backend images once.
5. Tag each image with the Git SHA/release and record its digest.
6. Promote the same digest through environments; do not rebuild per environment.

Images must not contain `.env` files, cloud credentials, database URIs or private
keys. Generate an SBOM and sign/provenance-attest production artifacts in line
with [SLSA](https://slsa.dev/spec/).

## Environment progression

```text
feature validation -> development -> staging -> production
```

Each environment has independent namespace, credentials, database, ingress,
state and approval policy. Production never reuses development Terraform state,
MongoDB, secrets, or mutable image tags.

## Standard rollout

1. Validate configuration and confirm required image URIs exist.
2. Apply secrets integration and wait for `mongo-secret` readiness.
3. Deploy database dependencies when explicitly in scope.
4. Deploy backend and wait for readiness/rollout completion.
5. Run backend health and representative read checks.
6. Deploy frontend and admin, then verify ingress routes.
7. Observe errors, latency, restarts and database health during a soak window.
8. Record commit, image digests, parameters, approver, timestamps and evidence.

Kubernetes Deployments use rolling updates with readiness probes and sufficient
capacity to avoid serving an unready revision. Follow the official
[Kubernetes deployment rollout guidance](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/).

## Strategy selection

| Strategy | Use when | Requirements |
|---|---|---|
| Rolling update | Routine backward-compatible releases | Readiness probes; mixed-version compatibility |
| Canary | Higher-risk backend or UI change | Traffic split, metrics, automatic abort thresholds |
| Blue/green | Major runtime/config change needing instant switch | Duplicate capacity and controlled data compatibility |
| Recreate | Development-only stateful dependency | Explicit downtime and verified backup |

Rolling update is the default. Canary is preferred for significant production
changes once traffic management and automated analysis are available.

## Database deployment safety

Database changes must be backward compatible with both old and new application
versions. Use expand/migrate/contract and back up before irreversible work.
Never delete/recreate the MongoDB pod as a credential or connectivity fix unless
durable storage and a tested restoration point are confirmed.

The current single MongoDB deployment is not production-grade. Before production,
adopt a managed/replicated topology with encrypted persistence, monitoring,
automated backup, restore exercises, disruption budgets and capacity planning.

## Release gates

- Required review and successful CI checks.
- No unresolved critical/high vulnerability above policy.
- Immutable image digest and provenance available.
- Secrets synchronized without values appearing in logs.
- Rollout completes within timeout; all replicas ready.
- Health, catalog read, and approved transaction smoke tests pass.
- Error rate, latency and saturation stay within the release baseline.

## Rollback

Rollback application code by redeploying the last verified image digests through
Jenkins. `kubectl rollout undo` is an emergency mechanism, not the durable release
record. Roll back immediately for health-check failure, sustained error/latency
regression, crash loops, data corruption risk, or security exposure.

Database rollback normally means forward remediation because data written by the
new version may be incompatible with old code. Restore from backup only under an
incident plan that accounts for data loss and recovery objectives.

## Production improvements

- protected environments and separation of deploy/approve roles;
- canary analysis with objective success/error budgets;
- PodDisruptionBudgets, topology spread and autoscaling;
- OpenTelemetry traces and release annotations;
- signed images, admission policy and SBOM retention;
- scheduled disaster-recovery tests with measured RPO/RTO.

## Post-deployment evidence

Retain the pipeline URL, source commit, image digests, environment, configuration
version, Terraform/Kubernetes plan summary, approvals, test output, rollout
status, monitoring snapshot, incidents, and rollback decision. Evidence must not
contain secrets or customer data.
