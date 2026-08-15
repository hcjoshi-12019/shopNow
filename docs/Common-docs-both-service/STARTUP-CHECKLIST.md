# Common Startup and Operations Checklist

This file is the shared checklist for both the application service and the infrastructure service in this project.

## 1. Project Overview

- App service: `shopNow/`
- Infra service: `herovired-infra/`
- Common workflow: prepare prerequisites, run app locally or in Docker, validate config, then deploy to Kubernetes or CI/CD.

---

## 2. Prerequisites Checklist

### Required tools

- [ ] Git
- [ ] Node.js 18+ and npm
- [ ] Docker Desktop or Docker Engine
- [ ] Docker Compose
- [ ] AWS CLI
- [ ] kubectl
- [ ] Helm
- [ ] Terraform
- [ ] Ansible
- [ ] Jenkins CLI or Jenkins access (if using CI/CD)

### Verify tools

```bash
node -v
npm -v
docker --version
docker compose version
aws --version
kubectl version --client
helm version
terraform version
ansible --version
```

---

## 3. ShopNow Service Checklist

### 3.1 Start the full app locally

From the `shopNow/` folder:

```bash
docker compose up --build
```

Then open the app:

- Frontend: http://localhost:3000
- Admin: http://localhost:3002
- Backend API: http://localhost:5000
- MongoDB: mongodb://localhost:27017/shopnow

### 3.2 Start services individually

#### Backend

```bash
cd shopNow/backend
npm install
npm run dev
```

#### Frontend

```bash
cd shopNow/frontend
npm install
npm start
```

#### Admin

```bash
cd shopNow/admin
npm install
npm start
```

### 3.3 Build production bundles

```bash
cd shopNow/frontend
npm run build

cd ../admin
npm run build
```

### 3.4 Stop app stack

```bash
cd shopNow
docker compose down
```

### 3.5 Reset local Docker state

```bash
docker compose down -v --remove-orphans
docker system prune -f
```

### 3.6 Useful app checks

```bash
cd shopNow/backend
npm test
# if tests are added later

curl http://localhost:5000
curl http://localhost:3000
curl http://localhost:3002
```

### 3.7 Git checklist for app repo

- [ ] Check branch status
- [ ] Review changed files
- [ ] Remove generated folders like `node_modules` and local `.env` from tracking
- [ ] Commit meaningful changes only
- [ ] Push to remote branch

```bash
cd shopNow
git status
git add .
git commit -m "feat: update app or deployment setup"
git push origin <branch-name>
```

---

## 4. Infra Service Checklist

### 4.1 Prerequisites for infra repo

From the `herovired-infra/` folder:

```bash
cd herovired-infra
ls
```

Common infra folders:

- `terraform/`
- `ansible/`
- `kubernetes/`
- `helm/`
- `scripts/`
- `pipelines/`
- `config/`

### 4.2 Validate infra environment

```bash
cd herovired-infra
aws sts get-caller-identity
kubectl cluster-info
kubectl get nodes
```

### 4.3 Terraform commands

```bash
cd herovired-infra/terraform
terraform init
terraform validate
terraform plan
terraform apply
```

To destroy infrastructure when needed:

```bash
terraform destroy
```

### 4.4 Kubernetes commands

```bash
kubectl get ns
kubectl get pods -A
kubectl get svc -A
kubectl get ingress -A
kubectl apply -f herovired-infra/kubernetes/
```

### 4.5 Helm commands

```bash
helm lint ./helm
helm template ./helm
helm install shopnow ./helm
helm upgrade --install shopnow ./helm
helm uninstall shopnow
```

### 4.6 Ansible commands

```bash
cd herovired-infra/ansible
ansible-playbook -i inventories/generated/hosts playbooks/configure-management.yml
ansible-playbook -i inventories/generated/hosts playbooks/validate-management.yml
```

### 4.7 Jenkins / CI commands

```bash
cd herovired-infra
make lint
make validate
```

If using the repo-level pipeline runner:

```bash
cd herovired-infra
jenkinsfile-runner --help
```

### 4.8 Infra repo cleanup checklist

- [ ] Ignore logs and generated artifacts
- [ ] Do not push temporary `*.log` files
- [ ] Do not push local runner folders created by Jenkins or JFR
- [ ] Keep only meaningful config, scripts, and manifests
- [ ] Verify branch is clean before push

```bash
cd herovired-infra
git status
git add .
git commit -m "chore: update infra config or scripts"
git push origin main
```

---

## 5. Common Release and Validation Checklist

Before pushing any repo, confirm:

- [ ] Dependencies are installed
- [ ] Environment variables are set
- [ ] Docker or Kubernetes services are healthy
- [ ] No local secrets or generated folders are staged
- [ ] Only meaningful files are committed
- [ ] Remote branch is correct
- [ ] README or setup docs are updated if commands changed

---

## 6. Recommended Order of Work

1. Start with app repo checks and local Docker validation.
2. Validate infra prereqs and cluster access.
3. Apply Terraform or Kubernetes config changes.
4. Build and push images if required.
5. Run deployment validation.
6. Commit and push only the required files.

---

## 7. Quick Commands Summary

### App service

```bash
cd shopNow
docker compose up --build
cd backend && npm install && npm run dev
cd ../frontend && npm install && npm start
cd ../admin && npm install && npm start
```

### Infra service

```bash
cd herovired-infra
aws sts get-caller-identity
kubectl get nodes
cd terraform && terraform init && terraform plan
cd ../ansible && ansible-playbook -i inventories/generated/hosts playbooks/validate-management.yml
```
