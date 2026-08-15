# Release SOP for ShopNow and Infra Deployment

This document is the day-to-day operational release checklist for deploying the application and infrastructure services without missing the critical steps.

---

## 1. Scope

This SOP covers:

- application code updates in `shopNow/`
- Docker image build and ECR push
- EKS rollout and runtime validation
- infra deployment coordination via `herovired-infra/`
- rollback and monitoring guidance

---

## 2. Roles and Responsibilities

### Application developer

- modifies app code in frontend, admin, or backend
- validates local app behavior before release
- ensures only required files are committed
- triggers the application pipeline
- checks app health after deployment

### Infra/deployment engineer

- ensures AWS, EKS, and namespace are ready
- validates infra config and deployment manifests
- checks ECR and cluster state
- monitors pod rollout and app health
- handles rollback if deployment is unhealthy

---

## 3. Pre-Release Checklist

Before any deployment, confirm the following:

- [ ] Correct git branch is selected.
- [ ] Only meaningful files are changed.
- [ ] No local secrets or generated folders are staged.
- [ ] Docker is running.
- [ ] AWS CLI is authenticated.
- [ ] `kubectl` can reach the cluster.
- [ ] ECR repos exist for frontend, admin, and backend.
- [ ] Namespace is present.
- [ ] Target cluster name and AWS region are confirmed.
- [ ] Deployment parameters are correct in Jenkins.

### Quick validation commands

```bash
aws sts get-caller-identity
kubectl get nodes
kubectl get ns
aws ecr describe-repositories --region ap-south-1
```

---

## 4. Build and Push Flow

### App release flow

1. Update application code.
2. Commit only the required service files.
3. Push to the target branch.
4. Trigger Jenkins app pipeline or run the deployment script.
5. The pipeline detects which service changed.
6. Docker image is built for the affected service(s).
7. Docker image is tagged and pushed to ECR.
8. Infra pipeline is triggered automatically if configured.

### Typical commands

```bash
cd shopNow
# Local build validation
cd frontend && npm install && npm run build
cd ../admin && npm install && npm run build
cd ../backend && npm install

# Docker build example
docker build -t shopnow-backend:<tag> ./backend
docker build -t shopnow-frontend:<tag> ./frontend
docker build -t shopnow-admin:<tag> ./admin

# ECR login and push
aws ecr get-login-password --region ap-south-1 | docker login --username AWS --password-stdin <account-id>.dkr.ecr.ap-south-1.amazonaws.com
```

---

## 5. ECR to EKS Deployment Flow

This is the core deployment flow:

1. Docker image is created in the app repo.
2. Image is pushed to ECR.
3. Infra repo applies or updates Kubernetes deployment manifests.
4. EKS pulls the new image.
5. Pods are recreated or rolled out with the new version.
6. App health is checked.

### Required checks before rollout

- [ ] target ECR image tag exists
- [ ] correct namespace is selected
- [ ] deployment manifest points to the correct image URI
- [ ] cluster is reachable
- [ ] rollout strategy is set for zero-downtime upgrades

### Kubernetes validation commands

```bash
kubectl get deployments -n shopnow-demo
kubectl get pods -n shopnow-demo
kubectl rollout status deployment/backend -n shopnow-demo
kubectl rollout status deployment/frontend -n shopnow-demo
kubectl rollout status deployment/admin -n shopnow-demo
kubectl logs -f deployment/backend -n shopnow-demo
```

---

## 6. Runtime Monitoring Checklist

After deployment, validate real usage.

### Basic app checks

- [ ] Frontend URL loads successfully.
- [ ] Admin URL loads successfully.
- [ ] Backend health endpoint responds.
- [ ] Product APIs return expected data.
- [ ] MongoDB connection is healthy.
- [ ] Ingress routes traffic correctly.
- [ ] No crash loops or repeated restarts.

### Health verification commands

```bash
kubectl get pods -A
kubectl get svc -n shopnow-demo
kubectl get ingress -n shopnow-demo
kubectl describe pod <pod-name> -n shopnow-demo
kubectl logs <pod-name> -n shopnow-demo --tail=100
curl http://<backend-host>/api/health
```

---

## 7. Rollback Procedure

If deployment fails or runtime quality is bad, rollback immediately.

### Rollback checklist

- [ ] identify last known good image tag
- [ ] confirm rollback image exists in ECR
- [ ] update deployment to last good image
- [ ] wait for rollout completion
- [ ] re-run health checks
- [ ] validate user-facing behavior again

### Rollback example

```bash
kubectl set image deployment/backend backend=<old-image-uri> -n shopnow-demo
kubectl rollout status deployment/backend -n shopnow-demo
kubectl get pods -n shopnow-demo
```

---

## 8. Deployment Sign-off

A deployment is only considered successful when all of the following are true:

- [ ] Docker image was built successfully.
- [ ] Image was pushed to ECR successfully.
- [ ] EKS rollout completed successfully.
- [ ] Pods are ready and healthy.
- [ ] Application endpoints respond correctly.
- [ ] No errors in logs or runtime events.
- [ ] User-facing application is functional.

---

## 9. Recommended Release Routine

Use this order for every release:

1. verify git status
2. validate configuration and credentials
3. build target image(s)
4. push to ECR
5. trigger or run infra deployment
6. monitor pod rollout
7. validate app health
8. sign off release or roll back

---

## 10. Related Docs

- [STARTUP-CHECKLIST.md](STARTUP-CHECKLIST.md)
- [DEPLOYMENT-CHECKLIST.md](DEPLOYMENT-CHECKLIST.md)
- [SERVICE-DEPENDENCY-REALTIME-ROLES.md](SERVICE-DEPENDENCY-REALTIME-ROLES.md)
- [shopNow/README.md](shopNow/README.md)
- [herovired-infra/README.md](herovired-infra/README.md)
