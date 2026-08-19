# ShopNow Architecture

## Purpose and scope

ShopNow is a three-tier demonstration commerce system consisting of a customer
web application, an administrator web application, a REST API, and MongoDB. The
application repository owns runtime source and container definitions; the
`herovired-infra` repository owns AWS, Kubernetes, ingress, secrets integration,
monitoring, and infrastructure deployment orchestration.

## Context and runtime flow

```text
Customer ──HTTPS──> Ingress ──> frontend (Nginx/React)
                                  │
Admin ─────HTTPS──> Ingress ──> admin (Nginx/React)
                                  │
                                  └──HTTP /api──> backend (Express :5000)
                                                      │
                                                      └──MongoDB :27017
```

The browser calls the API base configured at React build time. The backend
validates requests, persists products, invoices, and users, and exposes health
and analytics endpoints. Kubernetes service discovery resolves internal service
names. Only ingress-facing services should be reachable outside the cluster.

## Components

| Component | Technology | Responsibility | Default port |
|---|---|---|---:|
| `frontend` | React, Nginx | Product discovery, cart, checkout | 80 |
| `admin` | React, Nginx | Order search, status and collection workflow | 80 |
| `backend` | Node.js, Express, Mongoose | REST API and domain persistence | 5000 |
| `mongo` | MongoDB 7 | Products, invoices and users | 27017 |

## Data model

- `products`: catalog data, category, pricing, rating, image and stock.
- `invoices`: immutable order identity plus customer, items, total, payment and
  fulfillment state.
- `users`: customer identity keyed by email.

MongoDB is the persistence authority. The backend's in-memory MongoDB fallback
is development-only, ephemeral, and must never be considered a production
durability mechanism.

## Configuration and secrets

- `PORT` configures the backend listener; default is `5000`.
- `MONGODB_URI` is required for durable persistence.
- `REACT_APP_API_BASE_URL` is embedded during each React production build.
- Kubernetes secret `mongo-secret` is synchronized from AWS Secrets Manager by
  External Secrets and injected into MongoDB/backend workloads.
- Configuration belongs in environment variables; secrets must not appear in
  source, image layers, build arguments, logs, or documentation.

This follows the [Twelve-Factor configuration principle](https://12factor.net/config).

## Availability and scaling

Frontend and admin are stateless and horizontally scalable. Backend instances
are also stateless when all durable state is in MongoDB. A single in-cluster
MongoDB deployment is a development/capstone topology, not a highly available
production database. Production requires managed or replicated MongoDB,
encrypted persistent storage, automated backups, point-in-time recovery where
available, and routine restore tests.

Health probes must distinguish process health from dependency readiness.
Readiness prevents traffic from reaching an unready revision; liveness should
only restart a process that cannot recover by itself.

## Security boundaries

- TLS terminates at the controlled ingress or load balancer.
- Network policy should permit browser traffic only to public UI/API paths and
  backend-to-MongoDB traffic only on `27017`.
- Administrative and mutating API operations require authentication,
  authorization, validation, rate limiting, and auditable identity before a
  production launch.
- Database credentials require least privilege and scheduled rotation.
- Container images must use immutable digests/tags, non-root users where
  feasible, read-only filesystems, dropped Linux capabilities, and defined
  resource requests/limits.

Threat modeling and API controls should track the
[OWASP API Security Top 10](https://owasp.org/API-Security/).

## Observability

Minimum production telemetry:

- structured application logs with request/correlation ID;
- request rate, latency and error metrics by route and status class;
- pod restarts, saturation, MongoDB health and connection-pool metrics;
- deployment annotations carrying Git commit and image digest;
- alerts based on user-visible symptoms, not only host utilization.

Logs must redact authorization data, cookies, customer details, database URIs,
tokens, and passwords.

## Architectural decisions

1. REST/JSON is the integration boundary between UIs and backend.
2. Application images and infrastructure are versioned in separate repositories
   and joined through immutable image references.
3. MongoDB is reachable through cluster networking, not a public service.
4. AWS Secrets Manager is the secret authority; Kubernetes Secrets are runtime
   projections, not the primary store.
5. Terraform owns cloud foundation; Kubernetes manifests own workload desired
   state; Jenkins orchestrates validated changes.

## Standards and references

- [The Twelve-Factor App](https://12factor.net/)
- [Kubernetes concepts](https://kubernetes.io/docs/concepts/)
- [OWASP API Security](https://owasp.org/API-Security/)
- [OpenTelemetry](https://opentelemetry.io/docs/)
- [CNCF Cloud Native Security Whitepaper](https://github.com/cncf/tag-security/tree/main/security-whitepaper)
