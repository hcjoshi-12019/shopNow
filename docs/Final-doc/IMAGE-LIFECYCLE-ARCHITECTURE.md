# ShopNow Application: Image Lifecycle, Architecture & Operations Guide

**Document Version:** 1.0  
**Last Updated:** 2026-08-16  
**AWS Account:** 559272000457  
**EKS Cluster:** shopnow-app-eks  
**AWS Region:** ap-south-1

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Module Architecture](#module-architecture)
3. [Image Generation Pipeline](#image-generation-pipeline)
4. [ECR Registry Structure](#ecr-registry-structure)
5. [Image Tagging Strategy](#image-tagging-strategy)
6. [Responsibility Matrix](#responsibility-matrix)
7. [Build & Deployment Workflow](#build--deployment-workflow)
8. [Image Lifecycle Management](#image-lifecycle-management)
9. [Infra-App Synchronization](#infra-app-synchronization)
10. [Monitoring & Logging](#monitoring--logging)
11. [Operational Procedures](#operational-procedures)
12. [Troubleshooting](#troubleshooting)

---

## Architecture Overview

### High-Level System Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         GIT REPOSITORY                                      │
│  ┌──────────────────────┬──────────────────────┬──────────────────────┐     │
│  │   Frontend (React)   │  Backend (Node.js)   │  Admin (React)       │     │
│  │   src/               │  server.js           │  src/                │     │
│  │   Dockerfile         │  Dockerfile          │  Dockerfile          │     │
│  │   package.json       │  package.json        │  package.json        │     │
│  └──────────────────────┴──────────────────────┴──────────────────────┘     │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────┐       │
│  │  Jenkinsfile (Pipeline Orchestration)                            │       │
│  └──────────────────────────────────────────────────────────────────┘       │
└─────────────────────────────────────────────────────────────────────────────┘
                              │ Push/Commit
                              ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                    JENKINS PIPELINE TRIGGER                                 │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │ Stage 1: Checkout        (Clone repo)                              │    │
│  │ Stage 2: Initialize      (Detect changes, set IMAGE_TAG)           │    │
│  │ Stage 3: Build Parallel  (docker build for changed services)       │    │
│  │ Stage 4: Push to ECR     (aws ecr push)                            │    │
│  │ Stage 5: Hand Off to Infra (Trigger k8s deployment)               │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────┘
                              │ Service-specific tags
                              ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│              AWS ECR (Elastic Container Registry)                           │
│  Account: 559272000457 | Region: ap-south-1                                │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────┐       │
│  │ shopnow-dev (Single Repository - All Services)                  │       │
│  │                                                                   │       │
│  │ Tags:                                                            │       │
│  │ ├─ backend-snap-123-a1b2c3d                                      │       │
│  │ ├─ backend-snap-122-x9y8z7w                                      │       │
│  │ ├─ frontend-snap-123-a1b2c3d                                     │       │
│  │ ├─ frontend-snap-122-x9y8z7w                                     │       │
│  │ ├─ admin-snap-123-a1b2c3d                                        │       │
│  │ ├─ admin-snap-122-x9y8z7w                                        │       │
│  │ └─ ... (older versions)                                          │       │
│  └─────────────────────────────────────────────────────────────────┘       │
└─────────────────────────────────────────────────────────────────────────────┘
                              │ ImageURI
                              ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│          AWS EKS (Kubernetes Cluster: shopnow-app-eks)                      │
│  Region: ap-south-1 | Namespace: shopnow-ns                                │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │  Pod Replicas                                                        │  │
│  │  ┌──────────────────────┐  ┌──────────────────┐  ┌──────────────┐  │  │
│  │  │ backend-snap-123... │  │ frontend-snap-123 │  │ admin-snap-123  │  │
│  │  │ (port 5000)         │  │ (port 3000)       │  │ (port 8080)  │  │  │
│  │  └──────────────────────┘  └──────────────────┘  └──────────────┘  │  │
│  │                                                                      │  │
│  │  Ingress: nginx-ingress (routes traffic to services)               │  │
│  │  Secrets: ECR credentials, DB credentials                         │  │
│  │  ConfigMaps: App configuration                                    │  │
│  │  Volumes: MongoDB persistent storage                              │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌─────────────────────┐
                    │ MongoDB Database    │
                    │ (Helm: statefulset) │
                    │ PVC: mongo-data     │
                    └─────────────────────┘
```

---

## Module Architecture

### 1. **Backend Service**

**Technology Stack:**
- Node.js + Express.js
- MongoDB (Atlas or self-hosted)
- Port: 5000
- Health Check: `/health`

**Responsibilities:**
- REST API endpoints for business logic
- Database operations
- Authentication & Authorization
- Data validation & transformation

**Docker Image:**
```
Location: shopnow-dev (repository)
Tag: backend-snap-123-a1b2c3d
Dockerfile: backend/Dockerfile
Base Image: node:18-alpine (optimized for size)
Size: ~150-200MB
```

**Key Environment Variables:**
```bash
MONGODB_URI=mongodb://mongo-0.mongo:27017/shopnow
PORT=5000
LOG_LEVEL=info
NODE_ENV=production
```

---

### 2. **Frontend Service**

**Technology Stack:**
- React 18
- Node.js (for nginx reverse proxy)
- Port: 3000
- Health Check: `/index.html`

**Responsibilities:**
- User interface
- Client-side rendering
- State management
- Communication with Backend API

**Docker Image:**
```
Location: shopnow-dev (repository)
Tag: frontend-snap-123-a1b2c3d
Dockerfile: frontend/Dockerfile
Base Image: node:18-alpine (build) + nginx:alpine (runtime)
Final Size: ~50-80MB
```

---

### 3. **Admin Service**

**Technology Stack:**
- React 18
- Port: 8080
- Health Check: `/index.html`

**Responsibilities:**
- Admin dashboard
- User management
- System configuration
- Analytics & reporting

**Docker Image:**
```
Location: shopnow-dev (repository)
Tag: admin-snap-123-a1b2c3d
Dockerfile: admin/Dockerfile
Base Image: node:18-alpine (build) + nginx:alpine (runtime)
Final Size: ~50-80MB
```

---

## Image Generation Pipeline

### Pipeline Flow Diagram

```
┌──────────────────┐
│  Git Commit/Push │
│  to main/develop │
└────────┬─────────┘
         │ Webhook Trigger
         ▼
┌──────────────────────────────────┐
│  Jenkins Job Triggered            │
│  (shopnow-app build pipeline)     │
└────────┬─────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────┐
│  Stage: Checkout                             │
│  Action: git clone <repo>                    │
│  Artifact: Latest source code                │
└────────┬─────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────┐
│  Stage: Initialize                           │
│  Action: Detect changed files                │
│          Set IMAGE_TAG = BUILD_NUMBER + GIT_SHA
│  Example: IMAGE_TAG = "123-a1b2c3d"          │
│  Generate service-specific tags:             │
│  - BACKEND_TAG = "backend-snap-123-a1b2c3d" │
│  - FRONTEND_TAG = "frontend-snap-123-a1b2c3d" │
│  - ADMIN_TAG = "admin-snap-123-a1b2c3d"     │
└────────┬─────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────────────────────┐
│  Stage: Build in Parallel (Only changed services)            │
│                                                               │
│  If BUILD_FRONTEND == true:                                  │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  docker build -t shopnow-dev:frontend-snap-123-a1b2c3d │  │
│  │               --build-arg USER_NAME=harish \          │  │
│  │               frontend/                               │  │
│  │  Output: Image tagged with service name               │  │
│  └────────────────────────────────────────────────────────┘  │
│                                                               │
│  If BUILD_BACKEND == true:                                   │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  docker build -t shopnow-dev:backend-snap-123-a1b2c3d  │  │
│  │               backend/                                 │  │
│  └────────────────────────────────────────────────────────┘  │
│                                                               │
│  If BUILD_ADMIN == true:                                     │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  docker build -t shopnow-dev:admin-snap-123-a1b2c3d    │  │
│  │               --build-arg USER_NAME=harish \          │  │
│  │               admin/                                   │  │
│  └────────────────────────────────────────────────────────┘  │
│                                                               │
│  Processing: All builds run in parallel (faster CI/CD)       │
└────────┬─────────────────────────────────────────────────────┘
         │
         ▼
┌────────────────────────────────────────────────────────────────────┐
│  Stage: Push to ECR                                                │
│                                                                     │
│  Action 1: AWS Login                                               │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │ aws ecr get-login-password --region ap-south-1 | \          │  │
│  │   docker login --username AWS --password-stdin \            │  │
│  │   559272000457.dkr.ecr.ap-south-1.amazonaws.com             │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                     │
│  Action 2: Push with Service-Specific Tags                         │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │ docker push 559272000457.dkr.ecr.ap-south-1.amazonaws.com/  │  │
│  │   shopnow-dev:backend-snap-123-a1b2c3d                       │  │
│  │                                                               │  │
│  │ docker push 559272000457.dkr.ecr.ap-south-1.amazonaws.com/  │  │
│  │   shopnow-dev:frontend-snap-123-a1b2c3d                      │  │
│  │                                                               │  │
│  │ docker push 559272000457.dkr.ecr.ap-south-1.amazonaws.com/  │  │
│  │   shopnow-dev:admin-snap-123-a1b2c3d                         │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                     │
│  Images now in ECR with service-identifying tags                   │
└────────┬─────────────────────────────────────────────────────────┘
         │
         ▼
┌────────────────────────────────────────────────────────────────┐
│  Stage: Hand Off to Infra                                      │
│  Pass service-specific image URIs to infra job                │
└────────┬─────────────────────────────────────────────────────┘
         │
         ▼
┌────────────────────────────────────────────────────────────────┐
│  Deployment Complete                                           │
│                                                                 │
│  Pods Running:                                                 │
│  ├─ frontend-snap-123-a1b2c3d (3 replicas)                     │
│  ├─ backend-snap-123-a1b2c3d (2 replicas)                      │
│  └─ admin-snap-123-a1b2c3d (2 replicas)                        │
└────────────────────────────────────────────────────────────────┘
```

---

## ECR Registry Structure

### Registry Organization

**Account:** 559272000457  
**Region:** ap-south-1  
**Registry URL:** 559272000457.dkr.ecr.ap-south-1.amazonaws.com

### Repository Strategy: Single Repository with Service Tags

```
559272000457.dkr.ecr.ap-south-1.amazonaws.com/shopnow-dev

Tags by Service:
├── backend-snap-123-a1b2c3d  (Latest backend)
├── backend-snap-122-x9y8z7w  (Previous backend)
├── backend-snap-121-p5q4r3s  (Older backend)
│
├── frontend-snap-123-a1b2c3d (Latest frontend)
├── frontend-snap-122-x9y8z7w (Previous frontend)
├── frontend-snap-121-p5q4r3s (Older frontend)
│
├── admin-snap-123-a1b2c3d    (Latest admin)
├── admin-snap-122-x9y8z7w    (Previous admin)
└── admin-snap-121-p5q4r3s    (Older admin)
```

**Advantages:**
- Single repository (easier quota management)
- Service name in tag → clear identification
- "snap" prefix → obvious point-in-time snapshot
- Chronological ordering by build number
- All service versions tied to same build number when applicable

---

## Image Tagging Strategy

### Tagging Scheme

**Format:** `SERVICE_NAME-snap-BUILD_NUMBER-GIT_SHORT_SHA`

**Example:** `backend-snap-123-a1b2c3d`

### Components

| Component | Source | Example | Purpose |
|-----------|--------|---------|---------|
| SERVICE_NAME | Service identifier | backend, frontend, admin | Identifies which service (no ambiguity) |
| snap | Literal prefix | snap | Indicates build snapshot |
| BUILD_NUMBER | Jenkins | 123 | Sequential build counter, identifies build in Jenkins |
| GIT_SHORT_SHA | Git | a1b2c3d | First 7 chars of commit hash, identifies exact source code |

### Complete Image URI Examples

```
# Backend Image (with service name prefix)
559272000457.dkr.ecr.ap-south-1.amazonaws.com/shopnow-dev:backend-snap-123-a1b2c3d

# Frontend Image (with service name prefix)
559272000457.dkr.ecr.ap-south-1.amazonaws.com/shopnow-dev:frontend-snap-123-a1b2c3d

# Admin Image (with service name prefix)
559272000457.dkr.ecr.ap-south-1.amazonaws.com/shopnow-dev:admin-snap-123-a1b2c3d
```

**Explanation:**
- Repository path: `shopnow-dev` (single repo approach)
- Image tag: `{service}-snap-{build}-{git-sha}` (service-specific snapshot)

### Tag Generation Code (Jenkinsfile - UPDATED)

```groovy
// Line 104 in Jenkinsfile (UPDATED VERSION)
// Global IMAGE_TAG for tracking
env.IMAGE_TAG = "${env.BUILD_NUMBER}-${sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()}"

// Service-specific tags with service name prefix
env.BACKEND_TAG = "backend-snap-${env.IMAGE_TAG}"
env.FRONTEND_TAG = "frontend-snap-${env.IMAGE_TAG}"
env.ADMIN_TAG = "admin-snap-${env.IMAGE_TAG}"

// Example output:
// IMAGE_TAG = "123-a1b2c3d"
// BACKEND_TAG = "backend-snap-123-a1b2c3d"
// FRONTEND_TAG = "frontend-snap-123-a1b2c3d"
// ADMIN_TAG = "admin-snap-123-a1b2c3d"
```

### Why This Strategy?

| Benefit | Explanation |
|---------|------------|
| **Service Identification** | Service name in tag eliminates confusion; quick visual identification |
| **Snapshot Clarity** | `snap` prefix indicates point-in-time build snapshot |
| **Unique Identity** | BUILD_NUMBER ensures no duplicates; GIT_SHA ties to exact source |
| **Traceability** | Can link image back to: Service, Jenkins build #, Git commit, code state |
| **Single Registry** | All services in one repo (shopnow-dev) with service-specific tags |
| **Simple** | No manual tagging needed; fully automated |
| **Chronological** | BUILD_NUMBER naturally orders builds oldest → newest |
| **Debugging** | Easy to find which service produced which image |
| **Kubernetes Labels** | Service name matches deployment labels for easier correlation |

### Tagging Examples Over Time

```
BUILD #1: Backend change a1b2c3d  → backend-snap-1-a1b2c3d
BUILD #2: Frontend change x9y8z7w → frontend-snap-2-x9y8z7w
BUILD #3: Admin change p5q4r3s    → admin-snap-3-p5q4r3s
BUILD #4: Backend again a1b2c3d   → backend-snap-4-a1b2c3d
BUILD #5: All services m1n2o3p    → backend-snap-5-m1n2o3p
                                     frontend-snap-5-m1n2o3p
                                     admin-snap-5-m1n2o3p
```

**Key observations:**
- Service name immediately visible in tag
- BUILD_NUMBER preserves chronological order
- Multiple services in same build share build number
- Easy to identify "which service broke" in build #4

---

## Responsibility Matrix

### Who Does What in the CI/CD Pipeline

| Role | Responsibility | Trigger | Tools | Success Criteria |
|------|-----------------|---------|-------|-----------------|
| **Developer** | Write code, commit to git | Push to main/develop | Git, VS Code | Code passes linting, builds locally |
| **Jenkins Pipeline** | Build & push images with service-specific tags | Git webhook (auto) | Jenkins, Docker, AWS CLI | All changed services build & push with correct tag names |
| **Infra Job** | Deploy to EKS using service-tagged images | Hand-off from App Pipeline | Kubectl, Helm, Terraform | Pods running, replicas healthy, health checks passing |
| **DevOps/SRE** | Monitor, maintain pipeline | Continuous | CloudWatch, EKS Dashboards | Pipeline success rate >95%, zero deployment failures |
| **Security** | Image scanning | After push to ECR | ECR Image Scanning | No CRITICAL vulnerabilities allowed |

---

## Build & Deployment Workflow

### Step-by-Step Process

#### 1. **Change Detection** (Automatic)

```bash
# Jenkinsfile detects which service(s) changed
Example output:
  frontend/src/App.js
  backend/server.js
```

#### 2. **Service Selection & Tag Generation** (Automatic)

```bash
# Jenkins sets service-specific tags
BUILD_NUMBER=123
GIT_SHA=a1b2c3d
IMAGE_TAG=123-a1b2c3d

BACKEND_TAG=backend-snap-123-a1b2c3d
FRONTEND_TAG=frontend-snap-123-a1b2c3d
ADMIN_TAG=admin-snap-123-a1b2c3d
```

#### 3. **Docker Build** (Parallel Execution)

**Frontend:**
```bash
cd frontend/
docker build \
  --tag shopnow-dev:frontend-snap-123-a1b2c3d \
  --build-arg USER_NAME=harish \
  .
```

**Backend:**
```bash
cd backend/
docker build \
  --tag shopnow-dev:backend-snap-123-a1b2c3d \
  .
```

**Admin:**
```bash
cd admin/
docker build \
  --tag shopnow-dev:admin-snap-123-a1b2c3d \
  --build-arg USER_NAME=harish \
  .
```

#### 4. **ECR Authentication**

```bash
aws ecr get-login-password \
  --region ap-south-1 | \
  docker login \
  --username AWS \
  --password-stdin \
  559272000457.dkr.ecr.ap-south-1.amazonaws.com
```

#### 5. **Push to ECR with Service-Specific Tag**

```bash
docker push \
  559272000457.dkr.ecr.ap-south-1.amazonaws.com/shopnow-dev:backend-snap-123-a1b2c3d

docker push \
  559272000457.dkr.ecr.ap-south-1.amazonaws.com/shopnow-dev:frontend-snap-123-a1b2c3d

docker push \
  559272000457.dkr.ecr.ap-south-1.amazonaws.com/shopnow-dev:admin-snap-123-a1b2c3d
```

#### 6. **Hand Off to Infra Job**

```groovy
build job: 'herovired-infra', parameters: [
  string(name: 'BACKEND_IMAGE_URI', 
         value: '559272000457.dkr.ecr.ap-south-1.amazonaws.com/shopnow-dev:backend-snap-123-a1b2c3d'),
  string(name: 'FRONTEND_IMAGE_URI', 
         value: '559272000457.dkr.ecr.ap-south-1.amazonaws.com/shopnow-dev:frontend-snap-123-a1b2c3d'),
  string(name: 'ADMIN_IMAGE_URI', 
         value: '559272000457.dkr.ecr.ap-south-1.amazonaws.com/shopnow-dev:admin-snap-123-a1b2c3d'),
  string(name: 'IMAGE_TAG', value: '123-a1b2c3d'),
]
```

#### 7. **K8s Deployment** (Infra job responsibility)

```bash
# Infra job updates Kubernetes manifest with service-specific image URIs
kubectl set image deployment/backend \
  backend=559272000457.dkr.ecr.ap-south-1.amazonaws.com/shopnow-dev:backend-snap-123-a1b2c3d \
  -n shopnow-ns

kubectl set image deployment/frontend \
  frontend=559272000457.dkr.ecr.ap-south-1.amazonaws.com/shopnow-dev:frontend-snap-123-a1b2c3d \
  -n shopnow-ns

kubectl set image deployment/admin \
  admin=559272000457.dkr.ecr.ap-south-1.amazonaws.com/shopnow-dev:admin-snap-123-a1b2c3d \
  -n shopnow-ns
```

---

## Image Lifecycle Management

### Image Retention Policy

| Phase | Duration | Status | Action |
|-------|----------|--------|--------|
| **Active Development** | Until next version released | In use | Keep in registry, monitor metrics |
| **Previous Release** | 7 days | Available for rollback | Retain, do not delete |
| **Older Builds** | 7-30 days | Archived | Scan for vulnerabilities |
| **Old Builds** | >30 days | Deprecated | Delete if no critical vulnerabilities |

### Rollback Procedure

**If Latest Deployment Fails:**

```bash
# 1. Check previous backend image tag
aws ecr describe-images \
  --repository-name shopnow-dev \
  --region ap-south-1 \
  --query 'sort_by(imageDetails, &imagePushedAt)[-5:].{Tag:imageTags[0], Pushed:imagePushedAt}' \
  --output table | grep backend-snap

# Example output:
# Tag                        Pushed
# backend-snap-123-a1b2c3d  2026-08-16 10:30:45
# backend-snap-122-x9y8z7w  2026-08-16 08:15:20  ← Previous good tag

# 2. Manual rollback to previous version
kubectl set image deployment/backend \
  backend=559272000457.dkr.ecr.ap-south-1.amazonaws.com/shopnow-dev:backend-snap-122-x9y8z7w \
  -n shopnow-ns

# 3. Verify rollout
kubectl rollout status deployment/backend -n shopnow-ns
kubectl logs -f deployment/backend -n shopnow-ns
```

---

## Infra-App Synchronization

### Image URI Synchronization Flow

```
App Pipeline                                  Infra Pipeline
  │                                               │
  ├─ Build image: backend-snap-123-a1b2c3d      │
  ├─ Build image: frontend-snap-123-a1b2c3d    │
  ├─ Build image: admin-snap-123-a1b2c3d       │
  │                                              │
  ├─ Extract IMAGE URIs (service-specific)      │
  │  BACKEND_IMAGE_URI=shopnow-dev:             │
  │    backend-snap-123-a1b2c3d                 │
  │                                              │
  └─ Hand-off with IMAGE URIs ─────────────────► Receive IMAGE URIs
                                                 │
                                                 ├─ Read Kubernetes manifest
                                                 ├─ Update each service's image field
                                                 ├─ kubectl set image for each service
                                                 ├─ Wait for rollout completion
                                                 └─ Verify health checks pass
```

### Service Discovery via DNS

```yaml
# Kubernetes Service discovery inside cluster
# Frontend pod can reach backend via DNS:
http://backend:5000    # Load balances to backend pods
http://admin:8080      # Load balances to admin pods

# Full DNS names:
# backend.shopnow-ns.svc.cluster.local
# frontend.shopnow-ns.svc.cluster.local
# admin.shopnow-ns.svc.cluster.local

# Application code automatically finds services
const backendUrl = process.env.BACKEND_URL || 'http://backend:5000'
const response = await fetch(`${backendUrl}/api/users`)
```

---

## Monitoring & Logging

### 1. **Image Metrics in ECR**

```bash
# List all images in repository sorted by push time
aws ecr describe-images \
  --repository-name shopnow-dev \
  --region ap-south-1 \
  --query 'sort_by(imageDetails, &imagePushedAt)[-10:].{Tag:imageTags[0], Size:imageSizeInBytes, Pushed:imagePushedAt}' \
  --output table

# Check vulnerabilities for specific service images
aws ecr describe-image-scan-findings \
  --repository-name shopnow-dev \
  --image-id imageTag=backend-snap-123-a1b2c3d \
  --region ap-south-1 \
  --output table
```

### 2. **Pod & Container Metrics**

```bash
# Real-time pod resource usage
kubectl top pods -n shopnow-ns

# Pod restart counts (indicator of crashes)
kubectl get pods -n shopnow-ns -o json | \
  jq '.items[].status.containerStatuses[].restartCount'

# Pod events (failures, restarts, errors)
kubectl get events -n shopnow-ns --sort-by='.lastTimestamp'
```

### 3. **Application Logging**

```bash
# View logs from specific service
kubectl logs deployment/backend -n shopnow-ns --tail=100

# Follow logs in real-time
kubectl logs -f deployment/backend -n shopnow-ns

# Get logs from previous failed pod
kubectl logs pod/backend-746cc99cd-cqrgf \
  -n shopnow-ns \
  --previous
```

---

## Operational Procedures

### Procedure 1: Triggering Deployment with Service-Specific Tags

```bash
# Step 1: Access Jenkins
# http://jenkins-server:8080/job/shopnow-app/

# Step 2: Click "Build with Parameters"

# Step 3: Override parameters (optional):
FORCE_BUILD=true       # Rebuild all services

# Step 4: Jenkins auto-generates service-specific tags:
# BACKEND_TAG = backend-snap-124-a1b2c3d
# FRONTEND_TAG = frontend-snap-124-a1b2c3d
# ADMIN_TAG = admin-snap-124-a1b2c3d

# Step 5: Monitor build log
# Jenkins pushes images with service names in tags
```

### Procedure 2: View Images by Service in ECR

```bash
# List all backend snapshots
aws ecr describe-images \
  --repository-name shopnow-dev \
  --region ap-south-1 \
  --query "imageDetails[?contains(imageTags[0], 'backend-snap')] | sort_by(@, &imagePushedAt)[-5:]" \
  --output table

# List all frontend snapshots
aws ecr describe-images \
  --repository-name shopnow-dev \
  --region ap-south-1 \
  --query "imageDetails[?contains(imageTags[0], 'frontend-snap')] | sort_by(@, &imagePushedAt)[-5:]" \
  --output table

# List all admin snapshots
aws ecr describe-images \
  --repository-name shopnow-dev \
  --region ap-south-1 \
  --query "imageDetails[?contains(imageTags[0], 'admin-snap')] | sort_by(@, &imagePushedAt)[-5:]" \
  --output table
```

### Procedure 3: Rollback Specific Service

```bash
# Identify last 5 backend-snap images
aws ecr describe-images \
  --repository-name shopnow-dev \
  --region ap-south-1 \
  --query "imageDetails[?contains(imageTags[0], 'backend-snap')] | sort_by(@, &imagePushedAt)[-5:].{Tag:imageTags[0], Pushed:imagePushedAt}" \
  --output table

# Rollback backend only (keep frontend/admin unchanged)
kubectl set image deployment/backend \
  backend=559272000457.dkr.ecr.ap-south-1.amazonaws.com/shopnow-dev:backend-snap-122-x9y8z7w \
  -n shopnow-ns

# Verify rollback
kubectl rollout status deployment/backend -n shopnow-ns
kubectl get pods -n shopnow-ns -l app=backend
```

### Procedure 4: Verify Pod is Using Correct Image

```bash
# Check which image version is running
kubectl get pods -n shopnow-ns -o wide

# Get detailed image info for specific pod
kubectl get pod backend-746cc99cd-cqrgf -n shopnow-ns -o yaml | grep image:

# Expected output: image: 559272000457.dkr.ecr.ap-south-1.amazonaws.com/shopnow-dev:backend-snap-123-a1b2c3d
```

---

## Troubleshooting

### Issue 1: Pod Not Pulling Latest Image

**Symptom:** Pod running old image (backend-snap-122) when new image (backend-snap-123) is available

**Cause:** Image pull policy or pod not restarted

**Solution:**
```bash
# Force pod restart to pull new image
kubectl rollout restart deployment/backend -n shopnow-ns

# Verify new image pulled
kubectl get pods -n shopnow-ns -l app=backend
kubectl get pod backend-XXX -n shopnow-ns -o yaml | grep image:
```

### Issue 2: Cannot Pull Image from ECR

**Symptom:**
```
ImagePullBackOff
Failed to pull image "559272000457.dkr.ecr.ap-south-1.amazonaws.com/shopnow-dev:backend-snap-123-a1b2c3d"
```

**Solution:**
```bash
# Verify image exists in ECR
aws ecr describe-images \
  --repository-name shopnow-dev \
  --region ap-south-1 \
  --query "imageDetails[?contains(imageTags[0], 'backend-snap-123')]"

# Verify ECR credentials secret exists
kubectl get secret ecr-credentials -n shopnow-ns

# If missing, create it:
aws ecr get-login-password --region ap-south-1 | \
  kubectl create secret docker-registry ecr-credentials \
  --docker-server=559272000457.dkr.ecr.ap-south-1.amazonaws.com \
  --docker-username=AWS \
  --docker-password="$(aws ecr get-login-password --region ap-south-1)" \
  -n shopnow-ns
```

### Issue 3: Build Failure with Service-Specific Tags

**Symptom:** Jenkins build fails at "Build in Parallel" stage

**Solution:**
```bash
# Check Jenkins console log for docker build error
Jenkins UI → Build #123 → Console Output → Look for docker build errors

# Common fixes:
# 1. Dockerfile syntax error
#    Fix: Validate Dockerfile locally
#    docker build -t test:latest ./backend

# 2. Build arguments missing
#    Fix: Check --build-arg values in Jenkinsfile
#    Ensure USER_NAME is passed for frontend/admin

# 3. Missing files in build context
#    Fix: Check .dockerignore file
#    Verify all required files are in directory
```

---

## Maintenance Schedule

### Daily Tasks
- Monitor CloudWatch metrics
- Check Jenkins build success rate
- Review error logs

### Weekly Tasks
- Review ECR image scan results for all services
- Check pod restart counts
- Cleanup old images (>30 days)

### Monthly Tasks
- Update base Docker images
- Review resource limits
- Load testing

---

**Document Owner:** DevOps Team  
**Version:** 1.0 (Updated with Service-Specific Naming)  
**Last Review:** 2026-08-16

