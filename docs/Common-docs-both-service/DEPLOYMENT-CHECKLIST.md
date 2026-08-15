# Deployment Checklist for ShopNow and Infra Services

This checklist describes the end-to-end deployment flow for the two-service setup used in this project:

- `shopNow/` = application service
- `herovired-infra/` = infrastructure and deployment service

The intended delivery flow is:

1. Developer changes code in the app service.
2. Jenkins builds updated Docker images for the changed service(s).
3. Docker images are pushed to Amazon ECR.
4. The infra job receives the image tag / deployment event.
5. Kubernetes applies or updates the deployments for the affected service(s).
6. EKS pods restart or rollout with the latest image.
7. Developer validates health, logs, endpoints, and app behavior.

---

## 1. Deployment Architecture

### Service responsibilities

#### shopNow service

The application repo owns:

- `frontend/` - customer UI
- `admin/` - admin dashboard
- `backend/` - Node.js API service
- `Jenkinsfile` - app-side pipeline that detects changes and builds images
- deployment scripts such as `deploy-aws-eks.sh`

This repo is responsible for creating Docker images for the services and pushing them to ECR.

#### herovired-infra service

The infrastructure repo owns:

- `terraform/` - AWS and cluster setup
- `ansible/` - host and config automation
- `kubernetes/` - manifests for namespace, secret, services, ingress, and workloads
- `Jenkinsfile` - infra-side deployment workflow

This repo is responsible for deploying the latest image from ECR into EKS and applying the cluster manifests.

---

## 2. Required Prerequisites Before Deployment

### Developer pre-checks

- [ ] Confirm the correct branch is checked out.
- [ ] Confirm only required service files changed.
- [ ] Verify there are no secrets, local `.env` files, or node_modules staged for git.
- [ ] Confirm AWS credentials are valid.
- [ ] Confirm cluster access works with `kubectl`.
- [ ] Confirm Docker is running.
- [ ] Confirm the target AWS region and account ID are correct.
- [ ] Confirm the ECR repository exists for each service.
- [ ] Confirm the EKS cluster name and namespace are correct.

### Commands to validate environment

```bash
aws sts get-caller-identity
kubectl get nodes
kubectl get ns
aws ecr describe-repositories --region ap-south-1
```

### Required service configuration

- [ ] `AWS_REGION` is set correctly.
- [ ] `AWS_ACCOUNT_ID` is set correctly.
- [ ] `ECR_REPO_PREFIX` matches the repo naming convention.
- [ ] `K8S_NAMESPACE` matches the target namespace.
- [ ] `EKS_CLUSTER_NAME` points to the right cluster.
- [ ] `INFRA_JOB_NAME` is configured in the app Jenkins job.

---

## 3. Pipeline Flow for Each Deployment

### Step 1: Code change in app repo

Developer updates code in one or more service folders:

- `frontend/`
- `admin/`
- `backend/`

The app Jenkins pipeline checks git diffs to decide which service(s) changed.

### Step 2: App pipeline detects changed services

The Jenkinsfile performs change detection and sets flags, for example:

- `BUILD_FRONTEND`
- `BUILD_ADMIN`
- `BUILD_BACKEND`

This avoids unnecessary builds and deployment of unaffected services.

### Step 3: Build Docker image(s)

The app job builds one or more Docker images for the changed services.

Example flow:

```bash
docker build -t shopnow-frontend:<tag> ./frontend
docker build -t shopnow-admin:<tag> ./admin
docker build -t shopnow-backend:<tag> ./backend
```

The repo supports service-specific repository strategy or single shared repository strategy depending on configuration.

### Step 4: Authenticate to ECR

```bash
aws ecr get-login-password --region <region> | docker login --username AWS --password-stdin <account-id>.dkr.ecr.<region>.amazonaws.com
```

### Step 5: Push images to ECR

Example push flow:

```bash
docker tag shopnow-backend:<tag> <account-id>.dkr.ecr.<region>.amazonaws.com/<prefix>/backend:<tag>
docker push <account-id>.dkr.ecr.<region>.amazonaws.com/<prefix>/backend:<tag>
```

Repeat for frontend and admin.

### Step 6: Trigger infra deployment workflow

After Docker push succeeds, the app pipeline triggers the infra job, which is configured through `INFRA_JOB_NAME`.

The infra job then deploys the image tag to EKS using the cluster manifests and deployment definitions.

---

## 4. ECR to EKS Sync Checklist

This is the most important part of the deployment flow.

### Required deployment contract

The system assumes the following flow:

- Docker image is built in app repo
- image is pushed to ECR
- deployment manifests or Kubernetes deployment config reference the ECR image URI
- EKS rollout uses the new image tag
- pods come up with the new app version

### EKS update checklist

- [ ] Confirm the new image tag exists in ECR.
- [ ] Confirm the cluster is reachable via `kubectl`.
- [ ] Confirm the namespace is correct.
- [ ] Confirm the deployment resource references the ECR image.
- [ ] Confirm the updated image is not stale or cached incorrectly.
- [ ] Apply or update manifests to rollout the new image.
- [ ] Check that the deployment strategy is rolling update.
- [ ] Verify pods are replaced successfully.
- [ ] Validate health endpoints and application availability.

### Typical Kubernetes commands

```bash
kubectl get deployment -n shopnow-demo
kubectl get pods -n shopnow-demo
kubectl describe deployment backend -n shopnow-demo
kubectl rollout status deployment/backend -n shopnow-demo
kubectl rollout history deployment/backend -n shopnow-demo
kubectl logs -f deployment/backend -n shopnow-demo
```

For each service:

```bash
kubectl rollout status deployment/frontend -n shopnow-demo
kubectl rollout status deployment/admin -n shopnow-demo
kubectl rollout status deployment/backend -n shopnow-demo
```

---

## 5. End-to-End Developer Deployment Checklist

Use the following checklist every time a deployment is performed.

### 5.1 Prepare

- [ ] Confirm branch and commit are correct.
- [ ] Review the exact files changed.
- [ ] Validate no local secrets or temporary files are included.
- [ ] Confirm AWS credentials are valid.
- [ ] Confirm the EKS cluster is available.
- [ ] Confirm Docker daemon is running.
- [ ] Confirm ECR repositories exist.
- [ ] Confirm namespace exists.

### 5.2 Build images

- [ ] Run the app pipeline or equivalent local build command.
- [ ] Build frontend image.
- [ ] Build admin image.
- [ ] Build backend image.
- [ ] Validate Docker image creation succeeded.

### 5.3 Push to ECR

- [ ] Log in to ECR.
- [ ] Tag image(s) with correct repository and tag.
- [ ] Push image(s) to ECR.
- [ ] Confirm the image is visible in ECR.
- [ ] Confirm the image digest and tag match the intended release.

### 5.4 Trigger deployment

- [ ] Trigger app Jenkins job or deployment script.
- [ ] Confirm pipeline has the correct AWS region and account ID.
- [ ] Confirm infra job receives deployment signal.
- [ ] Confirm infra pipeline applies manifests or updates Kubernetes deployment.

### 5.5 Validate Kubernetes rollout

- [ ] Check deployment status.
- [ ] Check pod readiness.
- [ ] Check replica count.
- [ ] Check logs for startup errors.
- [ ] Ensure no crashloop or image-pull errors.
- [ ] Verify old pods are replaced by new pods.

### 5.6 Post-deploy testing

- [ ] Frontend loads successfully.
- [ ] Admin loads successfully.
- [ ] Backend health endpoint responds.
- [ ] Product APIs return data.
- [ ] Order or checkout flow works.
- [ ] MongoDB connection works.
- [ ] Ingress routes traffic correctly.
- [ ] External users can access the app.

---

## 6. Monitoring Checklist in Real Time

After deployment, check the running system in real time.

### Pod health

```bash
kubectl get pods -n shopnow-demo -w
kubectl get deployment -n shopnow-demo
kubectl get svc -n shopnow-demo
kubectl get ingress -n shopnow-demo
```

### Logs

```bash
kubectl logs -f deployment/backend -n shopnow-demo
kubectl logs -f deployment/frontend -n shopnow-demo
kubectl logs -f deployment/admin -n shopnow-demo
```

### Health checks

```bash
curl http://<frontend-url>
curl http://<admin-url>
curl http://<backend-url>/api/health
```

### Common production checks

- [ ] Pods are Running and Ready.
- [ ] No restart loops.
- [ ] No image pull failures.
- [ ] No CrashLoopBackOff events.
- [ ] Service endpoints are available.
- [ ] DB connectivity is healthy.
- [ ] Ingress returns application pages.
- [ ] Frontend and backend can communicate.

---

## 7. Service-Specific Deployment Checklist

### Frontend deployment

- [ ] Build frontend Docker image.
- [ ] Push image to ECR.
- [ ] Update frontend deployment to pull new image tag.
- [ ] Verify pod is recreated.
- [ ] Open frontend URL and confirm UI loads.
- [ ] Check browser console for runtime errors.

### Admin deployment

- [ ] Build admin Docker image.
- [ ] Push image to ECR.
- [ ] Update admin deployment.
- [ ] Verify admin pod rollout succeeds.
- [ ] Open admin URL and validate dashboard loads.

### Backend deployment

- [ ] Build backend Docker image.
- [ ] Push backend image to ECR.
- [ ] Update backend deployment.
- [ ] Check backend logs and readiness.
- [ ] Validate `/api/health` endpoint.
- [ ] Validate database connection and API calls.

---

## 8. Rollback Checklist

If deployment fails or the app becomes unstable:

- [ ] Identify the last known good image tag.
- [ ] Confirm the rollback target exists in ECR.
- [ ] Update the deployment to the previous image.
- [ ] Apply the rollback change.
- [ ] Verify pod rollout completes.
- [ ] Check health endpoints again.
- [ ] Verify the app returns to normal behavior.

### Rollback commands

```bash
kubectl set image deployment/backend backend=<old-image-uri> -n shopnow-demo
kubectl rollout status deployment/backend -n shopnow-demo
kubectl get pods -n shopnow-demo
```

---

## 9. Recommended Deployment Flow for Developers

Use this order every time:

1. Check git status and branch.
2. Validate only intended files changed.
3. Run build for affected service(s).
4. Push Docker image(s) to ECR.
5. Trigger infra pipeline.
6. Wait for rollout to finish.
7. Check pod health and logs.
8. Test application endpoint(s).
9. Confirm frontend/admin/backend are working.
10. Record release notes for the tag used.

---

## 10. Quick Command Summary

```bash
# App build and push
aws ecr get-login-password --region ap-south-1 | docker login --username AWS --password-stdin <account-id>.dkr.ecr.ap-south-1.amazonaws.com

docker build -t shopnow-backend:<tag> ./shopNow/backend
docker tag shopnow-backend:<tag> <account-id>.dkr.ecr.ap-south-1.amazonaws.com/<prefix>/backend:<tag>
docker push <account-id>.dkr.ecr.ap-south-1.amazonaws.com/<prefix>/backend:<tag>

# K8s validation
kubectl get deployment -n shopnow-demo
kubectl get pods -n shopnow-demo
kubectl rollout status deployment/backend -n shopnow-demo
kubectl logs -f deployment/backend -n shopnow-demo
```

---

## 11. Final Deployment Rule

Never deploy without verifying all three layers:

1. Docker image successfully built and pushed to ECR
2. EKS deployment rollout completed successfully
3. Application health and functionality are validated in real time

If any one of these three fails, the deployment is not considered successful.
