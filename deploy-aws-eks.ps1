$ErrorActionPreference = 'Stop'

$rootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$infraDir = Join-Path (Split-Path -Parent $rootDir) 'herovired-infra'
$awsRegion = if ($env:AWS_REGION) { $env:AWS_REGION } else { 'ap-south-1' }
$awsAccountId = if ($env:AWS_ACCOUNT_ID) { $env:AWS_ACCOUNT_ID } else { '559272000457' }
$ecrRepoPrefix = if ($env:ECR_REPO_PREFIX) { $env:ECR_REPO_PREFIX } else { 'shopnow' }
$k8sNamespace = if ($env:K8S_NAMESPACE) { $env:K8S_NAMESPACE } else { 'shopnow-ns' }
$clusterName = if ($env:EKS_CLUSTER_NAME) { $env:EKS_CLUSTER_NAME } else { 'shopnow-app-eks' }

if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
    throw 'AWS CLI is required but not installed.'
}

if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    throw 'kubectl is required but not installed.'
}

Write-Host "Configuring EKS context for cluster: $clusterName"
aws eks update-kubeconfig --region $awsRegion --name $clusterName

foreach ($svc in 'backend', 'frontend', 'admin') {
    Write-Host "Building $svc image..."
    docker build -t "$ecrRepoPrefix/$svc:latest" (Join-Path $rootDir $svc)
    aws ecr get-login-password --region $awsRegion | docker login --username AWS --password-stdin "$awsAccountId.dkr.ecr.$awsRegion.amazonaws.com"
    docker tag "$ecrRepoPrefix/$svc:latest" "$awsAccountId.dkr.ecr.$awsRegion.amazonaws.com/$ecrRepoPrefix/$svc:latest"
    docker push "$awsAccountId.dkr.ecr.$awsRegion.amazonaws.com/$ecrRepoPrefix/$svc:latest"
}

Write-Host 'Applying Kubernetes manifests from infra repo...'
kubectl apply -f (Join-Path $infraDir 'kubernetes/k8s-manifests/namespace/namespace.yaml')
kubectl apply -f (Join-Path $infraDir 'kubernetes/k8s-manifests/database/')
kubectl apply -f (Join-Path $infraDir 'kubernetes/k8s-manifests/backend/')
kubectl apply -f (Join-Path $infraDir 'kubernetes/k8s-manifests/frontend/')
kubectl apply -f (Join-Path $infraDir 'kubernetes/k8s-manifests/admin/')
kubectl apply -f (Join-Path $infraDir 'kubernetes/k8s-manifests/ingress/')

Write-Host 'Deployment complete.'
Write-Host "Verify with: kubectl get pods -n $k8sNamespace"
