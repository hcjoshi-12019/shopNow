# Jenkinsfile Update Guide: Service-Specific Image Naming

**Update Required:** Modify Jenkinsfile to use service-name-based image tags

**Current Format:** `123-a1b2c3d`  
**New Format:** `{service}-snap-123-a1b2c3d`  
**Example:** `backend-snap-123-a1b2c3d`, `frontend-snap-123-a1b2c3d`, `admin-snap-123-a1b2c3d`

---

## Changes Required in Jenkinsfile

### 1. **Update Environment Variables Section** (Lines 56-65)

**Current Code:**
```groovy
  environment {
    AWS_REGION = "${params.AWS_REGION}"
    AWS_ACCOUNT_ID = "${params.AWS_ACCOUNT_ID}"
    ECR_REPO_PREFIX = "${params.ECR_REPO_PREFIX}"
    ECR_REPOSITORY_STRATEGY = "${params.ECR_REPOSITORY_STRATEGY}"
    SINGLE_ECR_REPOSITORY = "${params.SINGLE_ECR_REPOSITORY}"
    USER_NAME = "${params.USER_NAME}"
    IMAGE_TAG = ''
    REPO_ROOT = ''
    CHANGESET = ''
    BUILD_FRONTEND = 'false'
    BUILD_ADMIN = 'false'
    BUILD_BACKEND = 'false'
  }
```

**Updated Code:**
```groovy
  environment {
    AWS_REGION = "${params.AWS_REGION}"
    AWS_ACCOUNT_ID = "${params.AWS_ACCOUNT_ID}"
    ECR_REPO_PREFIX = "${params.ECR_REPO_PREFIX}"
    ECR_REPOSITORY_STRATEGY = "${params.ECR_REPOSITORY_STRATEGY}"
    SINGLE_ECR_REPOSITORY = "${params.SINGLE_ECR_REPOSITORY}"
    USER_NAME = "${params.USER_NAME}"
    IMAGE_TAG = ''
    BACKEND_TAG = ''
    FRONTEND_TAG = ''
    ADMIN_TAG = ''
    REPO_ROOT = ''
    CHANGESET = ''
    BUILD_FRONTEND = 'false'
    BUILD_ADMIN = 'false'
    BUILD_BACKEND = 'false'
  }
```

---

### 2. **Update Initialize Stage** (Line ~104)

**Current Code:**
```groovy
          env.IMAGE_TAG = "${env.BUILD_NUMBER}-${sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()}"
```

**Updated Code:**
```groovy
          env.IMAGE_TAG = "${env.BUILD_NUMBER}-${sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()}"
          
          // Generate service-specific tags with service name prefix
          env.BACKEND_TAG = "backend-snap-${env.IMAGE_TAG}"
          env.FRONTEND_TAG = "frontend-snap-${env.IMAGE_TAG}"
          env.ADMIN_TAG = "admin-snap-${env.IMAGE_TAG}"
```

---

### 3. **Update Build in Parallel Stage - Frontend** (Lines ~165-180)

**Current Code:**
```groovy
          if (env.BUILD_FRONTEND == 'true') {
            buildTasks.frontend = {
              dir(serviceDir(env.REPO_ROOT, 'frontend')) {
                def repoBase = "${env.AWS_ACCOUNT_ID}.dkr.ecr.${env.AWS_REGION}.amazonaws.com"
                def frontendImage = (params.ECR_REPOSITORY_STRATEGY == 'single-repo' || params.SINGLE_ECR_REPOSITORY?.trim()) ?
                  "${repoBase}/${params.SINGLE_ECR_REPOSITORY ?: params.ECR_REPO_PREFIX}:frontend-${env.IMAGE_TAG}" :
                  "${repoBase}/${params.ECR_REPO_PREFIX}/frontend:${env.IMAGE_TAG}"
                env.FRONTEND_IMAGE_URI = frontendImage
                sh """
                  docker build \
                    --tag shopnow-frontend:${env.IMAGE_TAG} \
                    --tag ${frontendImage} \
                    --build-arg USER_NAME=${env.USER_NAME} .
                """
              }
            }
          }
```

**Updated Code:**
```groovy
          if (env.BUILD_FRONTEND == 'true') {
            buildTasks.frontend = {
              dir(serviceDir(env.REPO_ROOT, 'frontend')) {
                def repoBase = "${env.AWS_ACCOUNT_ID}.dkr.ecr.${env.AWS_REGION}.amazonaws.com"
                // Use service-specific tag (frontend-snap-BUILD-SHA)
                def frontendImage = (params.ECR_REPOSITORY_STRATEGY == 'single-repo' || params.SINGLE_ECR_REPOSITORY?.trim()) ?
                  "${repoBase}/${params.SINGLE_ECR_REPOSITORY ?: params.ECR_REPO_PREFIX}:${env.FRONTEND_TAG}" :
                  "${repoBase}/${params.ECR_REPO_PREFIX}:${env.FRONTEND_TAG}"
                env.FRONTEND_IMAGE_URI = frontendImage
                sh """
                  docker build \
                    --tag shopnow-frontend:${env.FRONTEND_TAG} \
                    --tag ${frontendImage} \
                    --build-arg USER_NAME=${env.USER_NAME} .
                """
              }
            }
          }
```

---

### 4. **Update Build in Parallel Stage - Backend** (Lines ~181-200)

**Current Code:**
```groovy
          if (env.BUILD_BACKEND == 'true') {
            buildTasks.backend = {
              dir(serviceDir(env.REPO_ROOT, 'backend')) {
                def repoBase = "${env.AWS_ACCOUNT_ID}.dkr.ecr.${env.AWS_REGION}.amazonaws.com"
                def backendImage = (params.ECR_REPOSITORY_STRATEGY == 'single-repo' || params.SINGLE_ECR_REPOSITORY?.trim()) ?
                  "${repoBase}/${params.SINGLE_ECR_REPOSITORY ?: params.ECR_REPO_PREFIX}:backend-${env.IMAGE_TAG}" :
                  "${repoBase}/${params.ECR_REPO_PREFIX}/backend:${env.IMAGE_TAG}"
                env.BACKEND_IMAGE_URI = backendImage
                sh """
                  docker build \
                    --tag shopnow-backend:${env.IMAGE_TAG} \
                    --tag ${backendImage} .
                """
              }
            }
          }
```

**Updated Code:**
```groovy
          if (env.BUILD_BACKEND == 'true') {
            buildTasks.backend = {
              dir(serviceDir(env.REPO_ROOT, 'backend')) {
                def repoBase = "${env.AWS_ACCOUNT_ID}.dkr.ecr.${env.AWS_REGION}.amazonaws.com"
                // Use service-specific tag (backend-snap-BUILD-SHA)
                def backendImage = (params.ECR_REPOSITORY_STRATEGY == 'single-repo' || params.SINGLE_ECR_REPOSITORY?.trim()) ?
                  "${repoBase}/${params.SINGLE_ECR_REPOSITORY ?: params.ECR_REPO_PREFIX}:${env.BACKEND_TAG}" :
                  "${repoBase}/${params.ECR_REPO_PREFIX}:${env.BACKEND_TAG}"
                env.BACKEND_IMAGE_URI = backendImage
                sh """
                  docker build \
                    --tag shopnow-backend:${env.BACKEND_TAG} \
                    --tag ${backendImage} .
                """
              }
            }
          }
```

---

### 5. **Update Build in Parallel Stage - Admin** (Lines ~201-220)

**Current Code:**
```groovy
          if (env.BUILD_ADMIN == 'true') {
            buildTasks.admin = {
              dir(serviceDir(env.REPO_ROOT, 'admin')) {
                def repoBase = "${env.AWS_ACCOUNT_ID}.dkr.ecr.${env.AWS_REGION}.amazonaws.com"
                def adminImage = (params.ECR_REPOSITORY_STRATEGY == 'single-repo' || params.SINGLE_ECR_REPOSITORY?.trim()) ?
                  "${repoBase}/${params.SINGLE_ECR_REPOSITORY ?: params.ECR_REPO_PREFIX}:admin-${env.IMAGE_TAG}" :
                  "${repoBase}/${params.ECR_REPO_PREFIX}/admin:${env.IMAGE_TAG}"
                env.ADMIN_IMAGE_URI = adminImage
                sh """
                  docker build \
                    --tag shopnow-admin:${env.IMAGE_TAG} \
                    --tag ${adminImage} \
                    --build-arg USER_NAME=${env.USER_NAME} .
                """
              }
            }
          }
```

**Updated Code:**
```groovy
          if (env.BUILD_ADMIN == 'true') {
            buildTasks.admin = {
              dir(serviceDir(env.REPO_ROOT, 'admin')) {
                def repoBase = "${env.AWS_ACCOUNT_ID}.dkr.ecr.${env.AWS_REGION}.amazonaws.com"
                // Use service-specific tag (admin-snap-BUILD-SHA)
                def adminImage = (params.ECR_REPOSITORY_STRATEGY == 'single-repo' || params.SINGLE_ECR_REPOSITORY?.trim()) ?
                  "${repoBase}/${params.SINGLE_ECR_REPOSITORY ?: params.ECR_REPO_PREFIX}:${env.ADMIN_TAG}" :
                  "${repoBase}/${params.ECR_REPO_PREFIX}:${env.ADMIN_TAG}"
                env.ADMIN_IMAGE_URI = adminImage
                sh """
                  docker build \
                    --tag shopnow-admin:${env.ADMIN_TAG} \
                    --tag ${adminImage} \
                    --build-arg USER_NAME=${env.USER_NAME} .
                """
              }
            }
          }
```

---

### 6. **Update Echo Statements in Initialize Stage** (Optional, for logging clarity)

Add after the tag generation (after line 107):
```groovy
          echo "Service-specific tags generated:"
          echo "  BACKEND_TAG: ${env.BACKEND_TAG}"
          echo "  FRONTEND_TAG: ${env.FRONTEND_TAG}"
          echo "  ADMIN_TAG: ${env.ADMIN_TAG}"
```

---

## Summary of Changes

### Files Modified
- `Jenkinsfile` (6 sections updated)

### Key Changes
1. ✅ Added `BACKEND_TAG`, `FRONTEND_TAG`, `ADMIN_TAG` environment variables
2. ✅ Generate service-specific tags: `{service}-snap-{build}-{sha}`
3. ✅ Updated docker build commands to use service-specific tags
4. ✅ Updated docker tags pushed to ECR use service names

### Before & After Examples

**Before (Current):**
```
Jenkins Build #123, commit a1b2c3d
  → Image tag: 123-a1b2c3d
  → ECR tag: shopnow-dev/backend:123-a1b2c3d
  → ECR tag: shopnow-dev/frontend:123-a1b2c3d
```

**After (New):**
```
Jenkins Build #123, commit a1b2c3d
  → Backend tag: backend-snap-123-a1b2c3d
  → Frontend tag: frontend-snap-123-a1b2c3d
  → Admin tag: admin-snap-123-a1b2c3d
  → ECR URI: shopnow-dev:backend-snap-123-a1b2c3d
  → ECR URI: shopnow-dev:frontend-snap-123-a1b2c3d
  → ECR URI: shopnow-dev:admin-snap-123-a1b2c3d
```

---

## Testing the Changes

### Step 1: Apply Jenkinsfile Updates
```bash
# Update the Jenkinsfile with changes above
# Commit to git
git add Jenkinsfile
git commit -m "feat: add service-specific image tagging (backend-snap, frontend-snap, admin-snap)"
git push origin main
```

### Step 2: Trigger a Build
```bash
# Option A: Manual trigger in Jenkins UI
Jenkins → shopnow-app → Build with Parameters → Build

# Option B: Force build via parameter
FORCE_BUILD=true
```

### Step 3: Verify in Console Log
```
Expected output in Jenkins console:
  IMAGE_TAG: 123-a1b2c3d
  BACKEND_TAG: backend-snap-123-a1b2c3d
  FRONTEND_TAG: frontend-snap-123-a1b2c3d
  ADMIN_TAG: admin-snap-123-a1b2c3d
  
  docker build ... -t shopnow-dev:backend-snap-123-a1b2c3d
  docker build ... -t shopnow-dev:frontend-snap-123-a1b2c3d
  docker build ... -t shopnow-dev:admin-snap-123-a1b2c3d
```

### Step 4: Verify in ECR
```bash
# List images in ECR
aws ecr describe-images \
  --repository-name shopnow-dev \
  --region ap-south-1 \
  --query 'imageDetails[*].imageTags[0]' \
  --output table

# Expected output:
# backend-snap-123-a1b2c3d
# frontend-snap-123-a1b2c3d
# admin-snap-123-a1b2c3d
```

### Step 5: Verify in Kubernetes
```bash
# Check deployed pods
kubectl get pods -n shopnow-ns -o wide

# Expected to see images with service names:
# backend-snap-123-a1b2c3d
# frontend-snap-123-a1b2c3d
# admin-snap-123-a1b2c3d
```

---

## Rollback Plan

If you need to revert to the old naming scheme:

```groovy
# Remove service-specific tag generation
# Revert to: IMAGE_TAG = "123-a1b2c3d" for all services
# Update docker tags back to: shopnow-dev/backend:123-a1b2c3d
```

---

## Benefits of This Change

✅ **Service Clarity:** Tag immediately identifies which service the image is for  
✅ **Snapshot Naming:** `snap` prefix makes it obvious this is a point-in-time snapshot  
✅ **Single Registry:** All services in one ECR repo with clear service-prefixed tags  
✅ **Better Troubleshooting:** Quickly identify "backend-snap-120 is broken" vs "frontend-snap-120"  
✅ **Cleaner K8s Labels:** Matches deployment service names for easier correlation  
✅ **Consistent Format:** All services follow same naming convention  

---

**Document:** Jenkinsfile Update Guide  
**Date:** 2026-08-16  
**Status:** Ready for Implementation

