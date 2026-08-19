# ShopNow service configuration and production operating model

This document explains how the ShopNow service is configured, why each setting exists, how it depends on the infrastructure repository, and how a DevOps team should operate it safely.

## 1. Service ownership and dependency boundary

| Area | Source of truth | Owner / change path | Why it matters |
|---|---|---|---|
| Frontend source and Dockerfile | \`shopNow/frontend/\` | ShopNow pull request and \`shopnow-service-dev\` Jenkins job | Customer UI must be built for its public path. |
| Admin source and Dockerfile | \`shopNow/admin/\` | ShopNow pull request and Jenkins job | Admin UI has a different asset base path but uses the same API. |
| Backend API and Dockerfile | \`shopNow/backend/\` | ShopNow pull request and Jenkins job | REST contract, order flow, database connection, and API behavior live here. |
| Image repositories and immutable tags | AWS ECR | Application Jenkins job | Every release is traceable to an exact build tag. |
| Kubernetes manifests, ingress, Mongo, secrets | \`herovired-infra/kubernetes/\` | Infrastructure pull request/Jenkins deployment stage | Runtime desired state belongs with infrastructure. |
| Cluster, networking, IAM, Helm and EKS auth | \`herovired-infra/terraform/\` | Infrastructure Terraform pipeline | Keeps cloud resources reproducible and reviewable. |
| Secret value | AWS Secrets Manager \`shopnow/mongo\` | Authorized secret rotation process | It is synchronized into the cluster without storing a secret in Git. |

The application repository owns application behavior and container build definitions. The infrastructure repository owns the cluster deployment shape. This separation prevents application commits from silently changing IAM, network, or cluster-level policy.

## 2. Current configuration contract

| Setting | Current production-like value | Defined by | Required alignment |
|---|---|---|---|
| Public base path | \`/shopnow\` | both Jenkinsfiles and ingress manifest | Must match the frontend build base. |
| Admin base path | \`/shopnow/admin\` | ShopNow Jenkinsfile and ingress manifest | Must match the admin build base. |
| API base path | \`/shopnow/api\` | ShopNow Jenkinsfile and ingress rewrite | Backend serves its internal routes under \`/api\`. |
| Backend container port | \`5000\` | backend Dockerfile + Kubernetes service | Service routes API traffic to this port. |
| UI container port | \`80\` | frontend/admin NGINX images + services | Ingress routes browser requests here. |
| Mongo service port | \`27017\` | Mongo deployment/service | Backend uses the in-cluster Mongo address/secret. |
| Namespace | \`shopnow-ns\` | infrastructure manifests | All workload access and policies scope to this namespace. |
| Image tag pattern | Jenkins build number + short Git SHA, e.g. \`25-df7ed225\` | ShopNow Jenkinsfile | Immutable and traceable release identity. |

For the browser builds, the critical build arguments are:

| Image | Build argument | Value |
|---|---|---|
| Frontend | \`PUBLIC_URL\` | \`/shopnow\` |
| Frontend | \`REACT_APP_API_BASE_URL\` | \`/shopnow/api\` |
| Admin | \`PUBLIC_URL\` | \`/shopnow/admin\` |
| Admin | \`REACT_APP_API_BASE_URL\` | \`/shopnow/api\` |

These are build-time values embedded in the static JavaScript bundles. Changing an ingress path without rebuilding the relevant UI will normally produce missing assets, bad routes, or calls to the wrong API location.

## 3. Request and data flow

1. A customer opens \`/shopnow/\`; the AWS load balancer forwards to ingress-nginx.
2. Ingress forwards the request to \`frontend-service:80\`.
3. The frontend sends API requests to \`/shopnow/api\`.
4. Ingress removes the external base prefix and forwards to \`backend-service:5000\` on the backend's \`/api/...\` routes.
5. The backend reads its MongoDB connection configuration from \`mongo-secret\`.
6. External Secrets creates or refreshes \`mongo-secret\` from AWS Secrets Manager secret \`shopnow/mongo\`.
7. MongoDB persists product, user, and invoice/order data.

The admin interface follows the same flow through \`/shopnow/admin/\` and the shared \`/shopnow/api\` endpoint. The API must remain backward compatible while old and new frontend pods can coexist during rollout.

## 4. CI/CD release strategy

The implemented deployment pattern is a traceable immutable-image release:

1. A pull request is reviewed and merged/pushed to the application branch.
2. GitHub calls Jenkins through its webhook endpoint.
3. \`shopnow-service-dev\` checks out the commit and builds frontend, admin, and backend images in parallel.
4. Jenkins tags each ECR image with the Jenkins build number and short Git SHA, for example \`25-df7ed225\`.
5. Jenkins pushes the immutable images to their ECR repositories.
6. Jenkins invokes \`herovired-infra-services\` with the exact three image references, \`RUN_TERRAFORM=false\`, and \`RUN_DEPLOYMENT=true\`.
7. The infrastructure pipeline renders and applies the Kubernetes manifests, waits for rollouts, and verifies the public health endpoint.

This is a GitOps-style desired-state pattern, even though Jenkins rather than a continuously running GitOps controller performs the apply: Git holds the manifests and Jenkins deploys explicit immutable artifacts. Treat direct manual \`kubectl\` changes only as emergency mitigation; capture them in a pull request immediately or they will be overwritten by the next deployment.

### Release gates

Before promotion, require:

- Code review and branch protection.
- Unit tests, linting, dependency/security scanning, and a successful container build.
- Image tag, Git SHA, and ECR image digest captured as release evidence.
- A successful deployment rollout for frontend, admin, backend, and Mongo.
- Public \`/shopnow/api/health\` check and a read-only smoke test of products/categories.
- Review of ingress 4xx/5xx traffic and backend error logs during a defined observation window.

Do not use mutable image names such as \`latest\`. The ECR repositories are immutable; a failed release can therefore be rolled back to a known tag without rebuilding it.

## 5. Blue/green and rollback strategy

The current Kubernetes Deployments perform a rolling update. This is suitable for low-risk changes with compatible APIs, but a production cutover should use a deliberate strategy:

| Change type | Preferred release pattern | Approval / validation |
|---|---|---|
| Static UI, compatible API | Rolling deployment with readiness gates | Verify assets, login, and API health. |
| Backend/API change | Canary or blue/green backend | Test health, error rate, latency, and order workflow before full traffic. |
| Database schema/data migration | Expand-contract migration with backward compatibility | Database backup, migration plan, and staged app rollout. |
| Ingress/path/domain change | Blue/green ingress or DNS cutover | Validate on a temporary host/path before switch. |
| Secret rotation | Update Secrets Manager, verify ExternalSecret, restart only consumers if necessary | Confirm no secret value in logs. |

For a blue/green deployment, maintain two deployment/service sets (for example \`backend-blue\` and \`backend-green\`) with labels such as \`version=blue\` and \`version=green\`. Deploy and test green without production ingress traffic, then change the stable service selector or ingress backend from blue to green. Keep blue available through the observation window so rollback is an immediate routing change. Production adoption requires corresponding manifest work in the infrastructure repository; do not claim blue/green is active until those resources and gates exist.

For the current release mechanism, roll back via Jenkins using previously verified immutable image tags. Kubernetes \`rollout undo\` can be an emergency action, but it must be followed by a Jenkins/Git desired-state update to prevent drift.

## 6. Application runtime patterns to enforce

| Pattern | Current position | Production target |
|---|---|---|
| Health endpoint | \`GET /api/health\` exists | Add Kubernetes readiness and liveness probes that use it. |
| Configuration | UI URLs compiled at image build; runtime secret via External Secrets | Keep non-secret config in versioned manifests; use secrets only for credentials. |
| API versioning | Single \`/api\` prefix | Introduce explicit versioning before breaking contract changes. |
| Idempotency | Order/invoice endpoint exists | Add idempotency keys for payment/order creation to avoid duplicates on retry. |
| Logging | Container output plus ingress logs | Structured JSON logs, request IDs, business event/audit fields, centralized retention. |
| Error handling | Backend errors appear in container logs | Standard error envelope, no secret/PII leakage, alertable error codes. |
| Data store | In-cluster MongoDB | Managed, backed-up Mongo-compatible service or managed database with HA and restore tests. |
| Autoscaling | Fixed replicas | HPA based on CPU/memory and custom API metrics, with cluster capacity planning. |

Order placement deserves special care. The API should log a correlation ID, non-sensitive order reference, state transition, and outcome—but never passwords, access tokens, complete addresses, or secret connection strings. The system should emit a durable business event when an order is accepted, paid, failed, or refunded; that event becomes the basis for customer support and reconciliation.

## 7. Security patterns

- Use a dedicated CI IAM role with short-lived credentials rather than a personal AWS user.
- Keep EKS Kubernetes access least-privilege and namespace-scoped. The management host has inspection/log/port-forward rights but cannot read secrets.
- Store only secret references in Git. The \`shopnow/mongo\` value lives in AWS Secrets Manager and is delivered by External Secrets.
- Use ECR immutable tags, enable scan-on-push, and block promotion of images with unacceptable findings.
- Pin base image versions and keep Node/Nginx images patched.
- Add network policies so only ingress can reach the UI/API services and only backend can reach MongoDB.
- Use a public DNS name, ACM certificate, HTTPS redirect, HSTS, secure cookies, CORS allow-list, and a web application firewall before customer launch.
- Sign or attest images and maintain an SBOM for each release when the delivery process matures.

## 8. Scaling, resilience, and database management

For production, configure at least two replicas for stateless frontend, admin, and backend workloads across failure domains, with:

- CPU and memory requests/limits.
- Pod disruption budgets.
- Readiness/liveness/startup probes.
- Horizontal Pod Autoscalers with sensible minimum replicas.
- Anti-affinity or topology spread constraints.
- Rolling-update values that keep capacity available during deployment.

Do not treat the current single MongoDB pod as production resilient. A production database requires encrypted storage, backups, point-in-time recovery where available, tested restore procedures, monitoring, credentials rotation, and a migration plan. Schema/data changes must be backward compatible while both release versions are live.

## 9. Change management procedure

### Application code change

1. Create a branch and pull request in \`shopNow\`.
2. Run local tests/builds and make sure the Docker build succeeds.
3. Review API compatibility, required configuration changes, and migration impact.
4. Merge only after required checks pass.
5. Record the Jenkins build number, Git SHA, image tags, and public smoke-test results.
6. Observe API error rate, ingress status codes, order flow, and pod restart count.

### Path or endpoint change

1. Change the ShopNow Jenkins build arguments and infrastructure ingress path in the same reviewed release.
2. Update user-facing documentation, monitoring probes, and client API configuration.
3. Deploy to a non-production environment or temporary route first.
4. Verify static asset URLs, UI navigation, API CORS behavior, and health checks.
5. Maintain the old route or redirect during the migration window if users may have bookmarks.

### Database or secret change

1. Back up and validate restore capability before a data-affecting change.
2. Use an expand-contract migration: add compatible schema/data first, deploy application support, migrate traffic/data, then remove old fields later.
3. Rotate \`shopnow/mongo\` only through Secrets Manager; wait for External Secrets synchronization.
4. Restart the backend only if it cannot reload changed credentials.
5. Confirm health and carefully inspect error logs without exposing secret values.

## 10. Incident response order

1. Determine the public symptom: customer UI, admin UI, API health, slow API, or failed order.
2. Check the public health URL and ingress controller 4xx/5xx logs.
3. Check backend deployment/pod readiness and backend logs.
4. Check Mongo pod, endpoints, and ExternalSecret condition without reading secret data.
5. Compare the deployed images with the Jenkins build tag and ECR digest.
6. Roll back through the release pipeline when a known-good immutable tag is available.
7. Preserve logs and timeline, then create corrective work in the appropriate repository.

See \`shopNow-related-commands-queries.md\` for exact copy/paste operational commands. See the infrastructure repository's architecture document for the shared AWS, EKS, ingress, IAM, and Jenkins topology.
