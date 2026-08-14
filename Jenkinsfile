def changeMatches(List<String> changedFiles, List<String> prefixes) {
  return changedFiles.any { file -> prefixes.any { prefix -> file == prefix || file.startsWith(prefix) } }
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

  parameters {
    string(name: 'AWS_REGION', defaultValue: 'ap-south-1', description: 'AWS region')
    string(name: 'AWS_ACCOUNT_ID', defaultValue: '495013583028', description: 'AWS account ID owning ECR')
    string(name: 'AWS_CREDENTIALS_ID', defaultValue: 'awsId', description: 'Jenkins AWS credentials ID')
    string(name: 'ECR_REPO_PREFIX', defaultValue: 'shopnow-dev', description: 'ECR repository prefix for the current environment (dev/prod)')
    choice(name: 'ECR_REPOSITORY_STRATEGY', choices: ['service-repos', 'single-repo'], description: 'Use service repositories (<prefix>/frontend) or one shared repository (<repo>:frontend-<tag>)')
    string(name: 'SINGLE_ECR_REPOSITORY', defaultValue: '', description: 'Shared ECR repository name for single-repo mode, for example shopnow-ecr-21-07-2027')
    string(name: 'USER_NAME', defaultValue: 'harish', description: 'Frontend and admin build arg used for public path customization')
    string(name: 'INFRA_JOB_NAME', defaultValue: 'shopnow-infra', description: 'Downstream Jenkins job name for infra deployment orchestration')
    booleanParam(name: 'TRIGGER_INFRA_DEPLOYMENT', defaultValue: true, description: 'Trigger the infra job after images are pushed')
    booleanParam(name: 'FORCE_BUILD', defaultValue: false, description: 'Force building and pushing all services regardless of detected changes')
  }

  options {
    skipDefaultCheckout()
    timestamps()
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '20', artifactNumToKeepStr: '10'))
    timeout(time: 75, unit: 'MINUTES')
  }

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
            echo 'No previous commit metadata found. Using repository file list for initial change detection.'
          }

          if (env.REPO_ROOT != '.') {
            changedFiles = changedFiles.collect { file ->
              file.startsWith("${env.REPO_ROOT}/") ? file.substring(env.REPO_ROOT.length() + 1) : file
            }
          }

          if (params.FORCE_BUILD) {
            echo 'FORCE_BUILD parameter set; forcing all services to build.'
            changedFiles = ['frontend/', 'admin/', 'backend/']
          } else if (!previousSha || previousSha == 'null' || !changedFiles || changedFiles.isEmpty() || changedFiles.every { it == null || it.trim().isEmpty() }) {
            echo 'No previous commit change set or first build detected; forcing all services to build.'
            changedFiles = ['frontend/', 'admin/', 'backend/']
          } else if (changedFiles.any { file -> file == 'Jenkinsfile' || file == 'README.md' || file.startsWith('.github/') || file.startsWith('docker/') || file.startsWith('scripts/') }) {
            echo 'Pipeline or repo-level configuration changed; forcing all services to build.'
            changedFiles = ['frontend/', 'admin/', 'backend/']
          }

          env.CHANGESET = changedFiles.take(100).join('\n')
          env.BUILD_FRONTEND = 'true'
          env.BUILD_ADMIN = 'true'
          env.BUILD_BACKEND = 'true'

          if (changedFiles && !changedFiles.isEmpty() && !changedFiles.every { it == null || it.trim().isEmpty() }) {
            env.BUILD_FRONTEND = changeMatches(changedFiles, ['frontend/']).toString()
            env.BUILD_ADMIN = changeMatches(changedFiles, ['admin/']).toString()
            env.BUILD_BACKEND = changeMatches(changedFiles, ['backend/']).toString()
          }

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
          def buildTasks = [:]

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
        expression { return env.BUILD_FRONTEND == 'true' || env.BUILD_ADMIN == 'true' || env.BUILD_BACKEND == 'true' }
      }
      steps {
        script {
          ensureAwsCredentials(this, params.AWS_CREDENTIALS_ID) {
            sh 'aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com'
          }

          def pushTasks = [:]

          if (env.BUILD_FRONTEND == 'true') {
            pushTasks.frontend = {
              sh 'docker push ${FRONTEND_IMAGE_URI}'
            }
          }

          if (env.BUILD_ADMIN == 'true') {
            pushTasks.admin = {
              sh 'docker push ${ADMIN_IMAGE_URI}'
            }
          }

          if (env.BUILD_BACKEND == 'true') {
            pushTasks.backend = {
              sh 'docker push ${BACKEND_IMAGE_URI}'
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

    stage('Hand Off to Infra') {
      when {
        expression {
          return params.TRIGGER_INFRA_DEPLOYMENT &&
            params.INFRA_JOB_NAME?.trim() &&
            (env.BUILD_FRONTEND == 'true' || env.BUILD_ADMIN == 'true' || env.BUILD_BACKEND == 'true')
        }
      }
      steps {
        script {
          echo "Triggering infra job ${params.INFRA_JOB_NAME} with image tag ${env.IMAGE_TAG}."
          try {
            build job: params.INFRA_JOB_NAME, wait: true, propagate: true, parameters: [
              string(name: 'AWS_REGION', value: env.AWS_REGION),
              string(name: 'AWS_ACCOUNT_ID', value: env.AWS_ACCOUNT_ID),
              string(name: 'ECR_REPO_PREFIX', value: env.ECR_REPO_PREFIX),
              string(name: 'ECR_REPOSITORY_STRATEGY', value: env.ECR_REPOSITORY_STRATEGY),
              string(name: 'SINGLE_ECR_REPOSITORY', value: env.SINGLE_ECR_REPOSITORY ?: ''),
              string(name: 'FRONTEND_IMAGE_URI', value: env.FRONTEND_IMAGE_URI ?: ''),
              string(name: 'ADMIN_IMAGE_URI', value: env.ADMIN_IMAGE_URI ?: ''),
              string(name: 'BACKEND_IMAGE_URI', value: env.BACKEND_IMAGE_URI ?: ''),
              string(name: 'IMAGE_TAG', value: env.IMAGE_TAG),
              string(name: 'DEPLOY_FRONTEND', value: env.BUILD_FRONTEND),
              string(name: 'DEPLOY_ADMIN', value: env.BUILD_ADMIN),
              string(name: 'DEPLOY_BACKEND', value: env.BUILD_BACKEND),
              booleanParam(name: 'RUN_TERRAFORM', value: false),
              booleanParam(name: 'RUN_ANSIBLE_AFTER_APPLY', value: false),
              booleanParam(name: 'RUN_DEPLOYMENT', value: true)
            ]
          } catch (err) {
            if (err.toString().contains('No item named')) {
              error("Infra handoff failed: Jenkins job '${params.INFRA_JOB_NAME}' was not found. Create a Pipeline job that points to herovired-infra/Jenkinsfile, or update INFRA_JOB_NAME.")
            }
            throw err
          }
        }
      }
    }

    stage('Summary') {
      steps {
        echo 'App pipeline finished after pushing images. Deployment orchestration is owned by the infra job.'
      }
    }
  }
}
