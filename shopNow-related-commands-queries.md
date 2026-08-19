# ShopNow service: operations, checks, and queries

This runbook is for the ShopNow application repository and its deployed workload. It uses the currently verified environment values. Do not paste AWS keys, database passwords, Jenkins credentials, or private keys into this document, Jenkins logs, or a terminal history.

## 1. Current deployment reference

| Item | Current value |
|---|---|
| AWS account / region | \`559272000457\` / \`ap-south-1\` |
| EKS cluster / namespace | \`shopnow-app-eks\` / \`shopnow-ns\` |
| Application branch | \`feature/shopnow-capston-project-v1\` |
| Application Jenkins job | \`shopnow-service-dev\` |
| Infrastructure Jenkins job | \`herovired-infra-services\` |
| Current verified image tag | \`25-df7ed225\` |
| Frontend image | \`559272000457.dkr.ecr.ap-south-1.amazonaws.com/shopnow-dev/frontend:25-df7ed225\` |
| Admin image | \`559272000457.dkr.ecr.ap-south-1.amazonaws.com/shopnow-dev/admin:25-df7ed225\` |
| Backend image | \`559272000457.dkr.ecr.ap-south-1.amazonaws.com/shopnow-dev/backend:25-df7ed225\` |
| Public ingress host | \`a2d7eee8d8179427fa36d881be68d64a-277526266.ap-south-1.elb.amazonaws.com\` |
| Public customer portal | \`http://a2d7eee8d8179427fa36d881be68d64a-277526266.ap-south-1.elb.amazonaws.com/shopnow/\` |
| Public admin portal | \`http://a2d7eee8d8179427fa36d881be68d64a-277526266.ap-south-1.elb.amazonaws.com/shopnow/admin/\` |
| Public API health check | \`http://a2d7eee8d8179427fa36d881be68d64a-277526266.ap-south-1.elb.amazonaws.com/shopnow/api/health\` |

The public address is an AWS Classic Load Balancer created by the ingress controller. It can change if the controller service is recreated; obtain the current address with the command in section 3 before publishing a URL.

## 2. Shell session and Kubernetes access

Run these from the management EC2 instance only after its IAM role and Kubernetes RBAC have been configured by the infrastructure pipeline.

~~~bash
export AWS_REGION=ap-south-1
export EKS_CLUSTER=shopnow-app-eks
export APP_NAMESPACE=shopnow-ns
export KUBECONFIG="$HOME/.kube/shopnow-app-eks"

aws eks update-kubeconfig \
  --region "$AWS_REGION" \
  --name "$EKS_CLUSTER" \
  --kubeconfig "$KUBECONFIG"

kubectl --kubeconfig "$KUBECONFIG" auth can-i get pods -n "$APP_NAMESPACE"
kubectl --kubeconfig "$KUBECONFIG" get pods -n "$APP_NAMESPACE"
~~~

Expected access is deliberately limited: the management host can inspect workloads, read workload logs, and create port-forwards in \`shopnow-ns\`. It must not read Kubernetes secrets.

If \`aws eks update-kubeconfig\` reports \`AccessDenied\` for \`eks:DescribeCluster\`, re-run the infrastructure pipeline with \`RUN_TERRAFORM=true\`; the Terraform-managed management-host role contains the required least-privilege discovery policy.

## 3. Application availability and public endpoint checks

~~~bash
export INGRESS_HOST=a2d7eee8d8179427fa36d881be68d64a-277526266.ap-south-1.elb.amazonaws.com
export APP_BASE_PATH=shopnow
export API_URL="http://$INGRESS_HOST/$APP_BASE_PATH/api"

curl --fail --silent --show-error --location \
  "http://$INGRESS_HOST/$APP_BASE_PATH/" -o /dev/null -w 'customer portal: %{http_code}\n'

curl --fail --silent --show-error --location \
  "http://$INGRESS_HOST/$APP_BASE_PATH/admin/" -o /dev/null -w 'admin portal: %{http_code}\n'

curl --fail --silent --show-error --location "$API_URL/health"
curl --fail --silent --show-error --location "$API_URL/products" | jq 'length'
curl --fail --silent --show-error --location "$API_URL/categories"
curl --fail --silent --show-error --location "$API_URL/analytics/dashboard"
~~~

Expected health response:

~~~json
{"status":"OK","message":"ShopNow API is running"}
~~~

Retrieve the currently assigned load balancer host instead of relying on a saved value:

~~~bash
kubectl --kubeconfig "$KUBECONFIG" get svc ingress-nginx-controller \
  -n ingress-nginx \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}{"\n"}'

kubectl --kubeconfig "$KUBECONFIG" get ingress -n "$APP_NAMESPACE"
~~~

The configured route contract is:

| Public path | Target service | Purpose |
|---|---|---|
| \`/shopnow/\` | \`frontend-service:80\` | customer UI |
| \`/shopnow/admin/\` | \`admin-service:80\` | administration UI |
| \`/shopnow/api/...\` | \`backend-service:5000\` | REST API |

The ingress rewrites an incoming \`/shopnow/api/health\` request to the backend's \`/api/health\` route. Keep the UI build paths, ingress base path, and Jenkins \`APP_BASE_PATH\` aligned.

## 4. Workload, rollout, and image verification

~~~bash
kubectl --kubeconfig "$KUBECONFIG" get deploy,rs,pods,svc,ingress \
  -n "$APP_NAMESPACE" -o wide

kubectl --kubeconfig "$KUBECONFIG" rollout status deployment/frontend \
  -n "$APP_NAMESPACE" --timeout=180s
kubectl --kubeconfig "$KUBECONFIG" rollout status deployment/admin \
  -n "$APP_NAMESPACE" --timeout=180s
kubectl --kubeconfig "$KUBECONFIG" rollout status deployment/backend \
  -n "$APP_NAMESPACE" --timeout=180s
kubectl --kubeconfig "$KUBECONFIG" rollout status deployment/mongo \
  -n "$APP_NAMESPACE" --timeout=180s

kubectl --kubeconfig "$KUBECONFIG" get deployment \
  frontend admin backend mongo \
  -n "$APP_NAMESPACE" \
  -o custom-columns=NAME:.metadata.name,READY:.status.readyReplicas,AVAILABLE:.status.availableReplicas,IMAGES:.spec.template.spec.containers[*].image
~~~

Compare the deployed image digest/tag with ECR:

~~~bash
aws ecr describe-images \
  --region ap-south-1 \
  --repository-name shopnow-dev/frontend \
  --image-ids imageTag=25-df7ed225 \
  --query 'imageDetails[0].{pushedAt:imagePushedAt,digest:imageDigest,size:imageSizeInBytes}' \
  --output table

aws ecr describe-images \
  --region ap-south-1 \
  --repository-name shopnow-dev/admin \
  --image-ids imageTag=25-df7ed225 \
  --query 'imageDetails[0].{pushedAt:imagePushedAt,digest:imageDigest,size:imageSizeInBytes}' \
  --output table

aws ecr describe-images \
  --region ap-south-1 \
  --repository-name shopnow-dev/backend \
  --image-ids imageTag=25-df7ed225 \
  --query 'imageDetails[0].{pushedAt:imagePushedAt,digest:imageDigest,size:imageSizeInBytes}' \
  --output table
~~~

The ECR repositories are immutable. A pipeline must publish a new tag for a new build; it cannot overwrite an existing tag. Never use \`latest\` for a release.

## 5. Application-level logs, API activity, and order investigation

Identify the currently running pods before tailing logs:

~~~bash
kubectl --kubeconfig "$KUBECONFIG" get pods -n "$APP_NAMESPACE" \
  -l app=backend -o wide
kubectl --kubeconfig "$KUBECONFIG" get pods -n "$APP_NAMESPACE" \
  -l app=frontend -o wide
kubectl --kubeconfig "$KUBECONFIG" get pods -n "$APP_NAMESPACE" \
  -l app=admin -o wide
~~~

Tail backend runtime output:

~~~bash
kubectl --kubeconfig "$KUBECONFIG" logs \
  -n "$APP_NAMESPACE" deployment/backend \
  --all-containers=true --prefix --since=60m --tail=300

kubectl --kubeconfig "$KUBECONFIG" logs \
  -n "$APP_NAMESPACE" deployment/backend \
  --all-containers=true --prefix --follow
~~~

Inspect previous crash output and the exact pod event when a container restarts:

~~~bash
BACKEND_POD=$(kubectl --kubeconfig "$KUBECONFIG" get pods -n "$APP_NAMESPACE" \
  -l app=backend -o jsonpath='{.items[0].metadata.name}')

kubectl --kubeconfig "$KUBECONFIG" logs -n "$APP_NAMESPACE" "$BACKEND_POD" --previous
kubectl --kubeconfig "$KUBECONFIG" describe pod -n "$APP_NAMESPACE" "$BACKEND_POD"
kubectl --kubeconfig "$KUBECONFIG" get events -n "$APP_NAMESPACE" \
  --sort-by='.lastTimestamp' | tail -n 40
~~~

Ingress controller access logs show the externally visible request path, method, status code, response size, and upstream. They are the first place to correlate customer API failures:

~~~bash
kubectl --kubeconfig "$KUBECONFIG" logs -n ingress-nginx \
  deployment/ingress-nginx-controller \
  --since=60m --tail=1000 |
  grep -E '(/shopnow/|/shopnow/api/|/shopnow/admin/)'

kubectl --kubeconfig "$KUBECONFIG" logs -n ingress-nginx \
  deployment/ingress-nginx-controller \
  --since=15m --tail=1500 |
  grep '/shopnow/api/' |
  grep -E ' (4[0-9]{2}|5[0-9]{2}) '
~~~

Use read-only APIs to inspect order activity. Do not include customer emails, tokens, or invoice payloads in incident tickets or public channels:

~~~bash
curl --fail --silent --show-error "$API_URL/invoices" |
  jq '[.[] | {id:._id,status:.status,total:.totalAmount,createdAt:.createdAt}]'

curl --fail --silent --show-error "$API_URL/analytics/dashboard" | jq .
~~~

The current backend emits startup and error logs but does not provide a complete structured audit trail for every HTTP request or every order transition. For production-grade order observability, add request correlation IDs, structured JSON application logs, and a central retention destination (for example CloudWatch Logs) before accepting customer traffic.

## 6. MongoDB and secret dependency checks

MongoDB uses the Kubernetes secret \`mongo-secret\`, synchronized by External Secrets from AWS Secrets Manager secret \`shopnow/mongo\`. Verify metadata only; do not print its value:

~~~bash
kubectl --kubeconfig "$KUBECONFIG" get externalsecret,secretstore,clustersecretstore \
  -n "$APP_NAMESPACE"

kubectl --kubeconfig "$KUBECONFIG" describe externalsecret mongo-secret \
  -n "$APP_NAMESPACE"

kubectl --kubeconfig "$KUBECONFIG" get secret mongo-secret \
  -n "$APP_NAMESPACE" \
  -o jsonpath='{.metadata.name}{" created="}{.metadata.creationTimestamp}{" keys="}{.data}{"\n"}'

kubectl --kubeconfig "$KUBECONFIG" get pods -n "$APP_NAMESPACE" -l app=mongo
kubectl --kubeconfig "$KUBECONFIG" logs -n "$APP_NAMESPACE" deployment/mongo \
  --since=60m --tail=200
~~~

Never run \`kubectl get secret mongo-secret -o yaml\`, \`kubectl describe secret\`, or a base64 decode command on a shared screen. Rotation is performed by updating \`shopnow/mongo\` in AWS Secrets Manager, verifying the ExternalSecret refresh, then restarting only the consumers if the application does not reload its environment dynamically.

## 7. Safe rollback and recovery

First identify the prior ReplicaSet and image. A rollback changes application state, so carry it out through a change record and validate the health endpoint afterwards.

~~~bash
kubectl --kubeconfig "$KUBECONFIG" rollout history deployment/frontend -n "$APP_NAMESPACE"
kubectl --kubeconfig "$KUBECONFIG" rollout history deployment/admin -n "$APP_NAMESPACE"
kubectl --kubeconfig "$KUBECONFIG" rollout history deployment/backend -n "$APP_NAMESPACE"

kubectl --kubeconfig "$KUBECONFIG" rollout undo deployment/frontend -n "$APP_NAMESPACE"
kubectl --kubeconfig "$KUBECONFIG" rollout undo deployment/admin -n "$APP_NAMESPACE"
kubectl --kubeconfig "$KUBECONFIG" rollout undo deployment/backend -n "$APP_NAMESPACE"

kubectl --kubeconfig "$KUBECONFIG" rollout status deployment/backend \
  -n "$APP_NAMESPACE" --timeout=180s
curl --fail --silent --show-error "$API_URL/health"
~~~

For a durable rollback, re-run the application Jenkins job with the intended immutable image tag and let it call the infrastructure deployment job. Avoid direct \`kubectl set image\` for routine releases because it causes Terraform/manifest drift.

## 8. Application CI/CD and local build checks

The application job builds frontend, admin, and backend images in parallel, pushes immutable tags to ECR, and triggers \`herovired-infra-services\` with \`RUN_TERRAFORM=false\` and \`RUN_DEPLOYMENT=true\`. The infrastructure job then applies the Kubernetes manifests with those explicit image references.

From the ShopNow repository:

~~~bash
git branch --show-current
git log -1 --oneline
git status --short

docker compose config
docker compose up --build
docker compose down

docker build \
  --build-arg PUBLIC_URL=/shopnow \
  --build-arg REACT_APP_API_BASE_URL=/shopnow/api \
  -t shopnow-frontend:local ./frontend

docker build \
  --build-arg PUBLIC_URL=/shopnow/admin \
  --build-arg REACT_APP_API_BASE_URL=/shopnow/api \
  -t shopnow-admin:local ./admin

docker build -t shopnow-backend:local ./backend
~~~

The frontend and admin browser bundles must be built with their production base paths:

| UI | \`PUBLIC_URL\` | \`REACT_APP_API_BASE_URL\` |
|---|---|---|
| Customer frontend | \`/shopnow\` | \`/shopnow/api\` |
| Admin frontend | \`/shopnow/admin\` | \`/shopnow/api\` |

The Jenkins job is available locally at \`http://localhost:8080/job/shopnow-service-dev/\`. Its console log must show the built Git SHA/tag, all three ECR pushes, and a successful downstream infrastructure deployment.

## 9. Failure-to-check mapping

| Symptom | Start with | Likely ownership |
|---|---|---|
| Customer/admin URL returns 404 | ingress paths and UI build paths | ShopNow + infra |
| API URL returns 502/504 | backend pods, backend service endpoints, ingress log | application/runtime |
| API URL returns 500 | backend logs and Mongo connectivity | ShopNow |
| New image cannot pull | pod describe event, ECR repository/tag and node egress | app image / infra network |
| \`mongo-secret\` missing | ExternalSecret describe and operator log | infrastructure secrets integration |
| Pipeline cannot reach GitHub | Jenkins/Docker DNS, then GitHub connectivity | Jenkins host |
| Deployment differs after manual change | Jenkins deployment stage and Git desired state | release process |

## 10. Production hardening backlog

- Put a stable DNS name in front of the load balancer, issue an ACM certificate, and require HTTPS before exposing customer traffic.
- Enable ECR scan-on-push and enforce image vulnerability review.
- Add readiness/liveness probes, CPU/memory requests and limits, and horizontal scaling rules to each application manifest.
- Replace the in-cluster MongoDB deployment with a managed, backed-up database for production data.
- Centralize structured application and ingress logs; configure alerts for 5xx rate, failed orders, pod restarts, image pull failures, and API latency.
- Use CI credentials with least privilege and rotate the current user-based AWS credentials.
