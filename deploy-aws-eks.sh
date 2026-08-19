#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="${ROOT_DIR}/../herovired-infra"
AWS_REGION="${AWS_REGION:-ap-south-1}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-559272000457}"
ECR_REPO_PREFIX="${ECR_REPO_PREFIX:-shopnow}"
K8S_NAMESPACE="${K8S_NAMESPACE:-shopnow-ns}"
CLUSTER_NAME="${EKS_CLUSTER_NAME:-shopnow-app-eks}"

if ! command -v aws >/dev/null 2>&1; then
  echo "AWS CLI is required but not installed."
  exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required but not installed."
  exit 1
fi

echo "Configuring EKS context for cluster: ${CLUSTER_NAME}"
aws eks update-kubeconfig --region "${AWS_REGION}" --name "${CLUSTER_NAME}"

for svc in backend frontend admin; do
  echo "Building ${svc} image..."
  docker build -t "${ECR_REPO_PREFIX}/${svc}:latest" "${ROOT_DIR}/${svc}"
  aws ecr get-login-password --region "${AWS_REGION}" | docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
  docker tag "${ECR_REPO_PREFIX}/${svc}:latest" "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_PREFIX}/${svc}:latest"
  docker push "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_PREFIX}/${svc}:latest"
done

echo "Applying Kubernetes manifests from infra repo..."
kubectl apply -f "${INFRA_DIR}/kubernetes/k8s-manifests/namespace/namespace.yaml"
kubectl apply -f "${INFRA_DIR}/kubernetes/k8s-manifests/database/"
kubectl apply -f "${INFRA_DIR}/kubernetes/k8s-manifests/backend/"
kubectl apply -f "${INFRA_DIR}/kubernetes/k8s-manifests/frontend/"
kubectl apply -f "${INFRA_DIR}/kubernetes/k8s-manifests/admin/"
kubectl apply -f "${INFRA_DIR}/kubernetes/k8s-manifests/ingress/"

echo "Deployment complete."
echo "Verify with: kubectl get pods -n ${K8S_NAMESPACE}"
