# ShopNow Project Contract

## Contract status

This document defines the stable boundaries between ShopNow clients, backend,
data store, CI/CD, and `herovired-infra`. Code and deployable configuration are
the implementation source of truth. A change that breaks this contract requires
an approved versioned migration and coordinated rollout.

## Ownership boundary

| Concern | ShopNow repository | Infrastructure repository |
|---|---|---|
| React and Express source | Owns | Consumes images |
| Dockerfiles and dependency lockfiles | Owns | Scans/deploys outputs |
| REST behavior and schemas | Owns | Routes traffic |
| AWS, EKS, IAM and networking | Consumes | Owns |
| Kubernetes workload manifests | Supplies image/runtime requirements | Owns |
| Secrets values | Never owns | References AWS Secrets Manager |
| Release evidence | Produces build metadata | Produces deployment evidence |

## Runtime configuration contract

| Variable | Consumer | Required behavior |
|---|---|---|
| `PORT` | Backend | Optional; defaults to `5000` |
| `MONGODB_URI` | Backend | Required outside local fallback; secret |
| `REACT_APP_API_BASE_URL` | Frontend/admin build | Public API base ending in `/api` |

Changing a React environment variable after an image is built does not rewrite
the compiled bundle; rebuild the image or use an explicitly designed runtime
configuration mechanism.

## HTTP API contract

Base path: `/api`. Payloads are JSON. Successful creation returns `201`; normal
reads/updates return `200`; invalid input returns `400`; missing resources return
`404`; unexpected failures return `500` without sensitive internals.

| Method | Path | Purpose |
|---|---|---|
| GET | `/health` | Service health |
| GET | `/products` | Paginated/filterable products |
| GET | `/products/{id}` | Product by ID |
| POST | `/products` | Create product |
| PUT | `/products/{id}` | Replace/update product fields |
| DELETE | `/products/{id}` | Delete product |
| POST | `/invoices` | Create order/invoice and decrement stock |
| GET | `/invoices` | Query invoices |
| GET | `/invoices/{id}` | Invoice by ID |
| GET | `/invoices/token/{token}` | Invoice by collection token |
| PUT | `/invoices/{id}/status` | Update fulfillment/payment status |
| PUT | `/invoices/token/{token}/collect` | Mark collected and paid |
| POST | `/users` | Create user |
| GET | `/users/{email}/orders` | Orders for email |
| GET | `/analytics/dashboard` | Aggregate operational dashboard |
| GET | `/categories` | Distinct product categories |
| POST | `/seed/products` | Destructive development seed operation |

Production evolution should publish an OpenAPI description and follow the
[OpenAPI Specification](https://spec.openapis.org/oas/latest.html). Additive,
backward-compatible fields are preferred. Removing/renaming fields, changing
types, status codes, validation, or meaning requires a new API version or a
documented compatibility window.

## Domain invariants

- Invoice number and collection token are unique.
- Invoice creation requires customer name, phone, non-empty items, and total.
- Order status is one of `pending`, `ready`, `collected`, or `cancelled`.
- Collection sets status to `collected`, payment to `paid`, and records time.
- Stock must never silently become negative; production implementation should
  use atomic validation/transactions for invoice creation and stock decrement.
- Money is currently numeric; production systems should use integer minor units
  or an exact decimal representation and an explicit currency.

## Delivery contract

Every deployable revision must provide three immutable images: `frontend`,
`admin`, and `backend`. Tags must identify a Git commit or release; `latest` is
not an acceptable production promotion unit. The application pipeline hands
explicit image URIs to the infrastructure deployment job. Deployment succeeds
only after rollout and health checks pass.

## Security contract

- No credentials, personal data, tokens, or decoded secrets in Git or logs.
- Mutating/admin endpoints must be protected before production exposure.
- Validate and bound all request bodies, query parameters, pagination and IDs.
- Apply least privilege to AWS IAM, Kubernetes RBAC and MongoDB users.
- Rotate any disclosed credential immediately and record the incident.
- Dependency and image vulnerability findings above the accepted threshold block
  promotion unless a time-bound risk exception is approved.

## Compatibility and change control

Use [Semantic Versioning](https://semver.org/) for releases. Each breaking change
must include consumer impact, migration, rollback, data compatibility, and an
expiration date for transitional behavior. Database changes use expand/migrate/
contract: deploy tolerant readers first, migrate data, then remove old fields in
a later release.

## Acceptance criteria

A change is releasable only when:

1. clean installs and production builds succeed from lockfiles;
2. automated tests and security checks pass;
3. health and representative API transactions pass;
4. image digests and source commit are recorded;
5. rollback is known and data changes are backward compatible;
6. documentation in these four canonical files remains accurate.
