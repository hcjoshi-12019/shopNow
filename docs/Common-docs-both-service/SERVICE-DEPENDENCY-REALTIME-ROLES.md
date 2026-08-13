# ShopNow and Infra Service Dependency and Runtime Roles

This document explains how the application service and the infrastructure service work together, and what each one does in the real application runtime.

---

## 1. High-Level Relationship

The project is split into two complementary repos:

- `shopNow/` = the actual business application
- `herovired-infra/` = the platform, deployment, and automation layer

They are dependent on each other, but in different directions:

1. The app repo depends on the infra repo for shared environment values, deployment conventions, cluster access, registry details, Kubernetes manifests, secrets, and CI/CD pipeline defaults.
2. The infra repo depends on the app repo for the application Docker images, build targets, image names, app ports, deployment manifests, and runtime behavior.
3. In real time, the app runs inside the infrastructure-managed environment, while the infra repo provides the network, storage, runtime platform, and security controls around it.

---

## 2. Real Dependency Map

### App service depends on infra service for:

- shared values in `herovired-infra/config/common.env`
- Jenkins helper values in `herovired-infra/jenkins/common.groovy`
- pipeline templates in `herovired-infra/pipelines/`
- Kubernetes manifest patterns and deployment conventions
- registry and namespace naming conventions
- AWS IAM, secrets, and external secret setup
- cluster access and infrastructure bootstrap

### Infra service depends on app service for:

- frontend, admin, and backend image names
- app container ports and health endpoints
- Docker build configuration
- service startup and shutdown behavior
- deployable manifests and application service contracts
- environment-specific deployment values used by Kubernetes/Helm

### Dependency chain in practice

```text
User / Browser
    ↓
Frontend (React UI)
    ↓
Backend API (Express)
    ↓
MongoDB / memory fallback
    ↓
Infrastructure layer provides:
- Kubernetes cluster
- Ingress / networking
- Secrets / IAM
- Storage / volumes
- ECR / registry
- Jenkins and deployment automation
```

---

## 3. What the ShopNow Service Does in Real Time

The `shopNow/` repo is the actual business application.

### 3.1 Frontend service

The frontend is a React application that serves the customer-facing website.

It is responsible for:

- rendering product pages
- browsing categories and items
- showing cart and checkout experience
- calling backend APIs for products and orders
- serving as the user-facing entry point to the application

In runtime, it usually runs behind a web server or container and reaches the backend through API requests.

### 3.2 Admin service

The admin service is a second React-based UI used for administration tasks.

It is responsible for:

- managing products
- reviewing orders
- controlling store data
- operations tasks for business administrators

In runtime, it is a separate frontend service, but it uses the same backend APIs and the same database layer.

### 3.3 Backend service

The backend is the main business logic layer, implemented with Express.js.

It is responsible for:

- exposing API routes for products, users, orders, and health checks
- validating requests
- connecting to MongoDB
- seeding sample data when the database is empty
- serving the application data layer for both frontend and admin UI

The backend is the real execution hub of the app. In `backend/server.js`, it:

- loads environment variables from the shared infra defaults when available
- creates Express middleware and API routes
- connects to MongoDB or a temporary in-memory MongoDB fallback
- exposes endpoints like `/api/health`, `/api/products`, and related order/user routes

### 3.4 MongoDB database

MongoDB stores the persistent product and order data for the application.

It is responsible for:

- product catalog storage
- user records
- invoice and order history
- data persistence for the e-commerce workflows

During local development, the backend may fall back to an in-memory MongoDB instance if a real database is not available.

---

## 4. What the Infra Service Does in Real Time

The `herovired-infra/` repo is not the application itself. It is the foundation that keeps the application running in a real environment.

### 4.1 Kubernetes and runtime environment

The infra repo provides the cluster resources needed for production-style deployments.

It is responsible for:

- namespace setup
- deployments and services
- ingress routing
- storage configuration
- external secret injection
- database access configuration
- service connectivity between app components

### 4.2 Terraform and cloud provisioning

The terraform layer is responsible for creating or managing the infrastructure base.

It handles:

- VPC and network setup
- EKS or cluster setup
- compute resources
- IAM roles
- storage and networking dependencies

### 4.3 Ansible and configuration automation

The Ansible part is responsible for host and system configuration tasks.

It handles:

- provisioning management hosts
- preparing nodes or services
- validating or enforcing configuration consistency

### 4.4 Jenkins and CI/CD automation

The infra repo supports pipeline automation for the whole project.

It is responsible for:

- image build orchestration
- pipeline parameter passing
- ECR or registry integration
- consistent app deployment flow

### 4.5 Secrets and security

Infrastructure also manages access and secret flow.

It handles:

- AWS IAM access
- ECR authentication
- Kubernetes secret setup for private registries
- external secrets for MongoDB or service credentials

---

## 5. End-to-End Runtime Flow

The real runtime flow is:

1. A user opens the frontend in the browser.
2. The frontend loads and makes API calls to the backend.
3. The backend validates requests and fetches or writes data from MongoDB.
4. The infrastructure layer ensures the backend, frontend, ingress, network, storage, and secrets are available.
5. Jenkins or deployment automation builds and pushes the app images when needed.
6. Kubernetes deploys the app containers and makes them reachable from the outside.

---

## 6. Practical Dependency Summary

| Component | Owns the business logic | Owns runtime platform | Typical responsibilities |
| --- | --- | --- | --- |
| `shopNow/` | Yes | No | App UI, backend API, business data flow |
| `herovired-infra/` | No | Yes | Cluster, networking, secrets, deployment automation |

---

## 7. Simple Conclusion

The `shopNow` repo is the actual product that users interact with, while the `herovired-infra` repo is the supporting platform that makes that product deployable, secure, and repeatable in real environments.

Without the app service, the infrastructure has no application to run.
Without the infra service, the app cannot be reliably deployed, exposed, or managed in Kubernetes and cloud environments.

They are dependent on each other, but they serve different layers of the system:

- `shopNow` = application behavior
- `herovired-infra` = environment, deployment, and runtime platform
