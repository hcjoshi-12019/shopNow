# ShopNow Command Reference

This is the executable operations runbook for the ShopNow application. Run
commands from the repository root unless a section says otherwise. Never paste,
log, or commit decoded secrets.

## Prerequisites

```bash
node --version
npm --version
docker --version
kubectl version --client
aws --version
mongosh --version
```

## Local development

Start all services with MongoDB:

```bash
docker compose config
docker compose up --build -d
docker compose ps
docker compose logs -f backend
```

Stop without deleting data:

```bash
docker compose down
```

Run components directly:

```bash
cd backend && npm ci && npm start
cd frontend && npm ci && npm start
cd admin && npm ci && npm start
```

Build and test:

```bash
cd backend && npm ci && npm audit
cd frontend && npm ci && npm test -- --watchAll=false && npm run build
cd admin && npm ci && npm test -- --watchAll=false && npm run build
```

## Local health checks

```bash
curl -fsS http://localhost:5000/api/health
curl -fsS http://localhost:5000/api/products
curl -fsS http://localhost:5000/api/categories
curl -I http://localhost:3000
```

## Kubernetes inspection

```bash
kubectl get namespace shopnow-ns
kubectl get deploy,pods,svc,ingress -n shopnow-ns
kubectl get events -n shopnow-ns --sort-by=.lastTimestamp
kubectl rollout status deployment/backend -n shopnow-ns --timeout=5m
kubectl rollout status deployment/frontend -n shopnow-ns --timeout=5m
kubectl rollout status deployment/admin -n shopnow-ns --timeout=5m
kubectl logs -n shopnow-ns deployment/backend --tail=200
```

Debug a failing workload:

```bash
kubectl describe pod -n shopnow-ns POD_NAME
kubectl logs -n shopnow-ns POD_NAME --previous
kubectl get endpoints -n shopnow-ns
kubectl exec -n shopnow-ns deployment/backend -- env | grep -E '^(PORT|NODE_ENV)='
```

Do not print `MONGODB_URI` or other secret values.

## MongoDB connection and checks

Confirm the deployment:

```bash
kubectl get pods -n shopnow-ns -l app=mongo
kubectl get service mongo -n shopnow-ns
```

Load the URI without displaying it and connect inside the cluster:

```bash
MONGODB_URI=$(kubectl get secret mongo-secret -n shopnow-ns \
  -o jsonpath='{.data.MONGODB_URI}' | base64 --decode)
kubectl exec -it -n shopnow-ns deployment/mongo -- mongosh "$MONGODB_URI"
unset MONGODB_URI
```

At the MongoDB prompt:

```javascript
use shopnow
show collections
db.products.find().pretty()
db.invoices.find().pretty()
db.users.find().pretty()
db.products.countDocuments()
db.invoices.countDocuments()
```

These host commands do not work unless MongoDB is explicitly exposed or
forwarded:

```bash
mongosh "mongodb://localhost:27017/shopnow" # times out without forwarding
mongosh "$MONGODB_URI"                      # `mongo` DNS works only in-cluster
```

Optional host access; keep the first command running in another terminal:

```bash
kubectl port-forward -n shopnow-ns service/mongo 27017:27017
MONGODB_URI=$(kubectl get secret mongo-secret -n shopnow-ns \
  -o jsonpath='{.data.MONGODB_URI}' | base64 --decode)
LOCAL_MONGODB_URI=$(printf '%s' "$MONGODB_URI" | sed 's/@mongo:27017/@localhost:27017/')
mongosh "$LOCAL_MONGODB_URI"
unset MONGODB_URI LOCAL_MONGODB_URI
```

## API smoke tests

Set the externally reachable API endpoint:

```bash
API_BASE_URL=http://localhost:5000/api
curl -fsS "$API_BASE_URL/health"
curl -fsS "$API_BASE_URL/products?page=1&limit=20"
curl -fsS "$API_BASE_URL/invoices?page=1&limit=20"
curl -fsS "$API_BASE_URL/analytics/dashboard"
```

Seed data is destructive because it clears current products. Use only in an
approved development environment:

```bash
curl -fsS -X POST "$API_BASE_URL/seed/products"
```

## Safe rollback and recovery

Prefer redeploying a previously verified immutable image through Jenkins. For
an emergency Kubernetes rollback:

```bash
kubectl rollout history deployment/backend -n shopnow-ns
kubectl rollout undo deployment/backend -n shopnow-ns
kubectl rollout status deployment/backend -n shopnow-ns --timeout=5m
```

Repeat for `frontend` or `admin` only when that component is affected. Confirm
health, logs, endpoints, and a representative transaction after rollback.

## Git hygiene

```bash
git status --short
git diff --check
git diff --stat
```

Commit source, lockfiles, and reviewed configuration together. Never commit
`.env`, decoded Kubernetes secrets, credentials, private keys, or local build
output.
