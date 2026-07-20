# CI/CD Pipeline Setup

ShopNow is split into two cooperating parts:

- `shopNow/`: the application service boundary that owns the React frontend, React admin panel, Node.js backend, and the root Jenkins pipeline.
- `herovired-infra/`: the infrastructure boundary that owns Terraform, Ansible, Kubernetes manifests, monitoring manifests, and Jenkins helper logic.

The two sides communicate through shared deployment contracts:

- Jenkins loads `herovired-infra/jenkins/common.groovy` to resolve shared defaults.
- The root `Jenkinsfile` builds application images and hands off deployment to the infra job.
- The infra `Jenkinsfile` deploys the application using manifests stored in `herovired-infra/kubernetes/`.
- Kubernetes services expose frontend, admin, and backend inside the cluster.
- The ingress routes external traffic to the app services.
- The backend reads `MONGODB_URI` from a Kubernetes secret created by the infra side.

## Service Boundaries

### shopNow service side

- `frontend/`: customer UI.
- `admin/`: admin dashboard.
- `backend/`: API service.
- `Jenkinsfile`: application-side CI/CD entrypoint that detects changed services and runs build/push steps in parallel where possible.

The app job only builds and pushes images, then optionally hands image tags to the infra job.

### herovired-infra side

- `herovired-infra/terraform/`: cluster and AWS foundation.
- `herovired-infra/ansible/`: management-host configuration.
- `herovired-infra/kubernetes/`: namespaces, secrets, services, ingress, and monitoring.
- `herovired-infra/pipelines/`: reusable Jenkins logic for infra jobs.
- `herovired-infra/Jenkinsfile`: infra-side CI/CD entrypoint that runs Terraform and Ansible when infra files change.

## Communication Flow

1. The infra Jenkins job provisions AWS networking, EKS, and the management host.
2. The infra Jenkins job prepares the management host so deployment tools can run.
3. The app Jenkins job builds the changed app images in parallel.
4. The app Jenkins job pushes those images to ECR.
5. The app Jenkins job optionally triggers the infra job with the image tag and changed-service flags.
6. The infra Jenkins job deploys the impacted Kubernetes workloads using manifests from `herovired-infra/`.
7. The frontend and admin services communicate with the backend over Kubernetes service DNS and ingress routing.
8. The backend communicates with MongoDB through `MONGODB_URI` sourced from the Kubernetes secret in `herovired-infra/kubernetes/k8s-manifests/database/mongo-secret.yaml`.

## Jenkins Parameters

The root `Jenkinsfile` exposes these parameters:

- `AWS_REGION`: AWS region for ECR and EKS.
- `AWS_ACCOUNT_ID`: AWS account that owns the ECR registry.
- `ECR_REPO_PREFIX`: Repository prefix, for example `harish-shopnow`.
- `USER_NAME`: Public path prefix used by the React build.
- `K8S_NAMESPACE`: Namespace used by the application workloads.
- `AWS_CREDENTIALS_ID`: Jenkins AWS credentials ID.
- `INFRA_JOB_NAME`: Downstream Jenkins job that runs the infra pipeline.
- `TRIGGER_INFRA_DEPLOYMENT`: Whether the app pipeline should trigger infra deployment after pushing images.

## Jenkins Job Wiring

Use two Jenkins Pipeline jobs:

- `shopnow-app`: points to the repo root `Jenkinsfile` and builds/pushes changed application images.
- `shopnow-infra`: points to `herovired-infra/Jenkinsfile` and handles Terraform, Ansible, and Kubernetes deployment.

The app job should keep `INFRA_JOB_NAME=shopnow-infra` so it can trigger the infra job automatically after publishing images. If you rename either job in Jenkins, update the matching parameter value in the app job.

The infra-side `herovired-infra/Jenkinsfile` exposes the Terraform, Ansible, and deployment parameters:

- `AWS_REGION`: AWS region used by Terraform and EKS.
- `AWS_ACCOUNT_ID`: AWS account used to resolve ECR image URIs.
- `TF_STATE_BUCKET`: S3 bucket for Terraform state.
- `LOCK_TABLE`: DynamoDB table for Terraform locking.
- `EKS_CLUSTER_NAME`: EKS cluster name.
- `ECR_REPO_PREFIX`: ECR repository prefix.
- `IMAGE_TAG`: Image tag to deploy.
- `DEPLOY_FRONTEND`, `DEPLOY_ADMIN`, `DEPLOY_BACKEND`: Service deployment flags.
- `AWS_CREDENTIALS_ID`: Jenkins AWS credentials ID.
- `SSH_PRIVATE_KEY_CREDENTIALS_ID`: SSH private key used for the management host.
- `REMOTE_USER`: SSH user for the management host.
- `K8S_NAMESPACE`: Application namespace.
- `MONITORING_NAMESPACE`: Monitoring namespace.
- `RUN_DEPLOYMENT`: Whether to deploy app workloads.

## Pipeline Behavior

The root pipeline is change-aware:

- Changes in `frontend/` only build and deploy the frontend path.
- Changes in `admin/` only build and deploy the admin path.
- Changes in `backend/` only build and deploy the backend path.
- Changes only in `frontend/`, `admin/`, or `backend/` build and push the affected services.
- If `TRIGGER_INFRA_DEPLOYMENT` is enabled, the app job passes image tags and service flags to the infra job.

The infra pipeline is also change-aware:

The infra pipeline is also change-aware:

- Changes in `herovired-infra/terraform/` run the Terraform path.
- Changes in `herovired-infra/ansible/` run the Ansible path.
- Terraform changes also refresh the Ansible inventory and management-host configuration.
- Deployment work runs in parallel for the impacted application services.

## GitHub Actions

The GitHub Actions workflow remains CI-only. It builds the three Docker images and smoke-tests the exposed health endpoints.
