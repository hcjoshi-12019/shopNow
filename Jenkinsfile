def changeMatches(List<String> changedFiles, List<String> prefixes) {
  return changedFiles.any { file ->
    def normalized = file?.trim() ?: ''
    prefixes.any { prefix -> normalized == prefix || normalized.startsWith(prefix) }
  }
}

def normalizeChangedFiles(List<String> changedFiles) {
  return changedFiles
    .findAll { it != null }
    .collect { it.trim() }
    .findAll { !it.isEmpty() }
}

def repoRoot(script) {
  if (script.fileExists('frontend/package.json') && script.fileExists('admin/package.json') && script.fileExists('backend/package.json')) {
    return '.'
  }
  if (script.fileExists('shopNow/frontend/package.json') && script.fileExists('shopNow/admin/package.json') && script.fileExists('shopNow/backend/package.json')) {
    return 'shopNow'
  }
  script.error('Could not locate frontend, admin, and backend package.json files in workspace.')
}

def serviceDir(String root, String serviceName) {
  return root == '.' ? serviceName : "${root}/${serviceName}"
}

def ensureAwsCredentials(script, String credentialsId, Closure body) {
  if (credentialsId?.trim()) {
    script.withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: credentialsId.trim()]]) {
      body()
    }
  } else {
    body()
  }
}

pipeline {
  agent any

  options {
    skipDefaultCheckout()
    timestamps()
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '20', artifactNumToKeepStr: '10'))
    timeout(time: 75, unit: 'MINUTES')
  }

  environment {
    AWS_REGION = 'ap-south-1'
    AWS_ACCOUNT_ID = '559272000457'
    AWS_CREDENTIALS_ID = 'awsId'
    ECR_REPO_PREFIX = 'shopnow-dev'
    ECR_REPOSITORY_STRATEGY = 'service-repos'
    SINGLE_ECR_REPOSITORY = ''
    USER_NAME = 'harish'
    INFRA_JOB_NAME = 'herovired-infra'
    TRIGGER_INFRA_DEPLOYMENT = 'true'
    FORCE_BUILD = 'false'
    IMAGE_TAG = ''
    REPO_ROOT = ''
    CHANGESET = ''
    BUILD_FRONTEND = 'false'
    BUILD_ADMIN = 'false'
    BUILD_BACKEND = 'false'
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Initialize') {
      steps {
        script {
          def resolvedRepoRoot = repoRoot(this)
          if (!resolvedRepoRoot || resolvedRepoRoot == 'null') {
            resolvedRepoRoot = '.'
          }
          env.REPO_ROOT = resolvedRepoRoot

          env.IMAGE_TAG = "${env.BUILD_NUMBER}-${sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()}"

          def currentSha = env.GIT_COMMIT?.trim()
          if (!currentSha || currentSha == 'null') {
            currentSha = sh(script: 'git rev-parse HEAD', returnStdout: true).trim()
          }

          def previousSha = env.GIT_PREVIOUS_SUCCESSFUL_COMMIT?.trim()
          if (!previousSha || previousSha == 'null') {
            previousSha = env.GIT_PREVIOUS_COMMIT?.trim()
          }
          if (!previousSha || previousSha == 'null') {
            def hasPrevious = sh(script: 'git rev-parse --verify HEAD~1 >/dev/null 2>&1', returnStatus: true) == 0
            if (hasPrevious) {
              previousSha = sh(script: 'git rev-parse HEAD~1', returnStdout: true).trim()
            }
          }

          def changedFiles = [] as List<String>
          if (previousSha && previousSha != 'null') {
            def changeSetText = sh(script: "git diff --name-only ${previousSha} ${currentSha}", returnStdout: true).trim()
            changedFiles = changeSetText ? changeSetText.split('\n') as List<String> : []
          } else {
            def allFiles = sh(script: "git ls-tree --name-only -r ${currentSha}", returnStdout: true).trim()
            changedFiles = allFiles ? allFiles.split('\n') as List<String> : []
            echo 'No previous commit metadata found. Falling back to current repository tree.'
          }

          if (env.REPO_ROOT != '.') {
            changedFiles = changedFiles.collect { file ->
              def normalized = file?.trim() ?: ''
              normalized.startsWith("${env.REPO_ROOT}/") ? normalized.substring(env.REPO_ROOT.length() + 1) : normalized
            }
          }

          // Code-driven pipeline: ALWAYS build and push images for every run.
          // No parameterized inputs - configuration is in code only.
          // This must not depend on stale env values from previous job runs.
          boolean buildFrontend = true
          boolean buildAdmin = true
          boolean buildBackend = true

          env.CHANGESET = 'frontend/\nadmin/\nbackend/'
          echo 'Code-driven pipeline: Building all service images for every run (FORCE_BUILD=' + env.FORCE_BUILD + ')'

          env.BUILD_FRONTEND = buildFrontend ? 'true' : 'false'
          env.BUILD_ADMIN = buildAdmin ? 'true' : 'false'
          env.BUILD_BACKEND = buildBackend ? 'true' : 'false'

          echo "Repository root: ${resolvedRepoRoot}"
          echo "Changed files (first 100):\n${env.CHANGESET ?: '<none>'}"
          echo "Frontend build required: ${env.BUILD_FRONTEND}"
          echo "Admin build required: ${env.BUILD_ADMIN}"
          echo "Backend build required: ${env.BUILD_BACKEND}"
        }
      }
    }

    stage('Build in Parallel') {
      steps {
        script {
          def buildFrontend = true
          def buildAdmin = true
          def buildBackend = true

          def buildTasks = [:]

          if (buildFrontend) {
            buildTasks.frontend = {
              dir(serviceDir(env.REPO_ROOT, 'frontend')) {
                def repoBase = "${env.AWS_ACCOUNT_ID}.dkr.ecr.${env.AWS_REGION}.amazonaws.com"
                def frontendImage = (env.ECR_REPOSITORY_STRATEGY == 'single-repo' || env.SINGLE_ECR_REPOSITORY?.trim()) ?
                  "${repoBase}/${env.SINGLE_ECR_REPOSITORY ?: env.ECR_REPO_PREFIX}:frontend-${env.IMAGE_TAG}" :
                  "${repoBase}/${env.ECR_REPO_PREFIX}/frontend:${env.IMAGE_TAG}"
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

          if (buildAdmin) {
            buildTasks.admin = {
              dir(serviceDir(env.REPO_ROOT, 'admin')) {
                def repoBase = "${env.AWS_ACCOUNT_ID}.dkr.ecr.${env.AWS_REGION}.amazonaws.com"
                def adminImage = (env.ECR_REPOSITORY_STRATEGY == 'single-repo' || env.SINGLE_ECR_REPOSITORY?.trim()) ?
                  "${repoBase}/${env.SINGLE_ECR_REPOSITORY ?: env.ECR_REPO_PREFIX}:admin-${env.IMAGE_TAG}" :
                  "${repoBase}/${env.ECR_REPO_PREFIX}/admin:${env.IMAGE_TAG}"
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

          if (buildBackend) {
            buildTasks.backend = {
              dir(serviceDir(env.REPO_ROOT, 'backend')) {
                def repoBase = "${env.AWS_ACCOUNT_ID}.dkr.ecr.${env.AWS_REGION}.amazonaws.com"
                def backendImage = (env.ECR_REPOSITORY_STRATEGY == 'single-repo' || env.SINGLE_ECR_REPOSITORY?.trim()) ?
                  "${repoBase}/${env.SINGLE_ECR_REPOSITORY ?: env.ECR_REPO_PREFIX}:backend-${env.IMAGE_TAG}" :
                  "${repoBase}/${env.ECR_REPO_PREFIX}/backend:${env.IMAGE_TAG}"
                env.BACKEND_IMAGE_URI = backendImage
                sh """
                  docker build \
                    --tag shopnow-backend:${env.IMAGE_TAG} \
                    --tag ${backendImage} .
                """
              }
            }
          }

          if (buildTasks.isEmpty()) {
            echo 'No service changes detected, skipping Docker build.'
          } else {
            parallel buildTasks
          }
        }
      }
    }

    stage('Push to ECR') {
      when {
        expression {
          return (env.BUILD_FRONTEND ?: 'true') == 'true' ||
                 (env.BUILD_ADMIN ?: 'true') == 'true' ||
                 (env.BUILD_BACKEND ?: 'true') == 'true'
        }
      }
      steps {
        script {
          def buildFrontend = (env.BUILD_FRONTEND ?: 'true') == 'true'
          def buildAdmin = (env.BUILD_ADMIN ?: 'true') == 'true'
          def buildBackend = (env.BUILD_BACKEND ?: 'true') == 'true'

          ensureAwsCredentials(this, env.AWS_CREDENTIALS_ID) {
            sh """
              aws ecr get-login-password --region "${AWS_REGION}" | \
              docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
            """
          }

          def pushTasks = [:]

          if (buildFrontend) {
            pushTasks.frontend = {
              sh "docker push \"${FRONTEND_IMAGE_URI}\""
            }
          }

          if (buildAdmin) {
            pushTasks.admin = {
              sh "docker push \"${ADMIN_IMAGE_URI}\""
            }
          }

          if (buildBackend) {
            pushTasks.backend = {
              sh "docker push \"${BACKEND_IMAGE_URI}\""
            }
          }

          if (pushTasks.isEmpty()) {
            echo 'No images to push.'
          } else {
            parallel pushTasks
          }
        }
      }
    }

    stage('Deployment Orchestration') {
      when {
        expression {
          def buildFrontend = (env.BUILD_FRONTEND ?: 'true') == 'true'
          def buildAdmin = (env.BUILD_ADMIN ?: 'true') == 'true'
          def buildBackend = (env.BUILD_BACKEND ?: 'true') == 'true'

          return env.TRIGGER_INFRA_DEPLOYMENT == 'true' &&
            env.INFRA_JOB_NAME?.trim() &&
            (buildFrontend || buildAdmin || buildBackend)
        }
      }
      steps {
        script {
          def buildFrontend = (env.BUILD_FRONTEND ?: 'true') == 'true'
          def buildAdmin = (env.BUILD_ADMIN ?: 'true') == 'true'
          def buildBackend = (env.BUILD_BACKEND ?: 'true') == 'true'

          echo "This app pipeline creates the dev ECR images and pushes them to ${env.ECR_REPO_PREFIX}. The deployment orchestrator will consume the built image URIs only."
          echo "Triggering deployment job ${env.INFRA_JOB_NAME} with image tag ${env.IMAGE_TAG}."
          try {
            build job: env.INFRA_JOB_NAME, wait: true, propagate: true, parameters: [
              string(name: 'AWS_REGION', value: env.AWS_REGION),
              string(name: 'AWS_ACCOUNT_ID', value: env.AWS_ACCOUNT_ID),
              string(name: 'ECR_REPO_PREFIX', value: env.ECR_REPO_PREFIX),
              string(name: 'ECR_REPOSITORY_STRATEGY', value: env.ECR_REPOSITORY_STRATEGY),
              string(name: 'SINGLE_ECR_REPOSITORY', value: env.SINGLE_ECR_REPOSITORY ?: ''),
              string(name: 'FRONTEND_IMAGE_URI', value: env.FRONTEND_IMAGE_URI ?: ''),
              string(name: 'ADMIN_IMAGE_URI', value: env.ADMIN_IMAGE_URI ?: ''),
              string(name: 'BACKEND_IMAGE_URI', value: env.BACKEND_IMAGE_URI ?: ''),
              string(name: 'IMAGE_TAG', value: env.IMAGE_TAG),
              string(name: 'DEPLOY_FRONTEND', value: buildFrontend ? 'true' : 'false'),
              string(name: 'DEPLOY_ADMIN', value: buildAdmin ? 'true' : 'false'),
              string(name: 'DEPLOY_BACKEND', value: buildBackend ? 'true' : 'false'),
              booleanParam(name: 'RUN_TERRAFORM', value: false),
              booleanParam(name: 'RUN_ANSIBLE_AFTER_APPLY', value: false),
              booleanParam(name: 'RUN_DEPLOYMENT', value: true)
            ]
          } catch (err) {
            if (err.toString().contains('No item named')) {
              error("Deployment orchestration failed: Jenkins job '${env.INFRA_JOB_NAME}' was not found. Create the deployment job or update INFRA_JOB_NAME.")
            }
            throw err
          }
        }
      }
    }

    stage('Summary') {
      steps {
        echo 'This app pipeline created the dev ECR images. Production promotion should read the final image from ECR instead of rebuilding it.'
      }
    }
  }
}
