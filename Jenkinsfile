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
    string(name: 'ECR_REPO_PREFIX', defaultValue: 'shopnow', description: 'ECR repository prefix')
    string(name: 'USER_NAME', defaultValue: 'harish', description: 'Frontend and admin build arg used for public path customization')
    string(name: 'INFRA_JOB_NAME', defaultValue: 'shopnow-infra', description: 'Downstream Jenkins job name for infra deployment orchestration')
    booleanParam(name: 'TRIGGER_INFRA_DEPLOYMENT', defaultValue: true, description: 'Trigger the infra job after images are pushed')
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

          def resolvedImageTag = "${env.BUILD_NUMBER}-${sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()}"
          env.IMAGE_TAG = resolvedImageTag

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
          def changeSetText = ''
          if (previousSha && previousSha != 'null') {
            changeSetText = sh(script: "git diff --name-only ${previousSha} ${currentSha}", returnStdout: true).trim()
            changedFiles = changeSetText ? changeSetText.split('\n') as List<String> : []
          } else {
            // First build or no previous commit metadata: treat repository files as changed.
            changeSetText = sh(script: "git ls-tree --name-only -r ${currentSha}", returnStdout: true).trim()
            changedFiles = changeSetText ? changeSetText.split('\n') as List<String> : []
            echo 'No previous commit metadata found. Using repository file list for initial change detection.'
          }

          // Safety net: never silently no-op when SCM metadata is unavailable.
          if (!changedFiles || changedFiles.isEmpty()) {
            echo 'Change detection returned no files; forcing application services to build to avoid false-success no-op.'
            changedFiles = ['frontend/', 'admin/', 'backend/']
          }

          // Keep env payload small and safe for logging.
          env.CHANGESET = changedFiles ? changedFiles.take(100).join('\n') : ''

          def frontendChanged = changeMatches(changedFiles, ['frontend/'])
          def adminChanged = changeMatches(changedFiles, ['admin/'])
          def backendChanged = changeMatches(changedFiles, ['backend/'])

          env.BUILD_FRONTEND = frontendChanged.toString()
          env.BUILD_ADMIN = adminChanged.toString()
          env.BUILD_BACKEND = backendChanged.toString()

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
                sh "docker build --tag shopnow-frontend:${IMAGE_TAG} --tag ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_PREFIX}/frontend:${IMAGE_TAG} --build-arg USER_NAME=${USER_NAME} ."
              }
            }
          }

          if (env.BUILD_ADMIN == 'true') {
            buildTasks.admin = {
              dir(serviceDir(env.REPO_ROOT, 'admin')) {
                sh "docker build --tag shopnow-admin:${IMAGE_TAG} --tag ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_PREFIX}/admin:${IMAGE_TAG} --build-arg USER_NAME=${USER_NAME} ."
              }
            }
          }

          if (env.BUILD_BACKEND == 'true') {
            buildTasks.backend = {
              dir(serviceDir(env.REPO_ROOT, 'backend')) {
                sh "docker build --tag shopnow-backend:${IMAGE_TAG} --tag ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_PREFIX}/backend:${IMAGE_TAG} ."
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
              sh "docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_PREFIX}/frontend:${IMAGE_TAG}"
            }
          }
          if (env.BUILD_ADMIN == 'true') {
            pushTasks.admin = {
              sh "docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_PREFIX}/admin:${IMAGE_TAG}"
            }
          }
          if (env.BUILD_BACKEND == 'true') {
            pushTasks.backend = {
              sh "docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_PREFIX}/backend:${IMAGE_TAG}"
            }
          }

          parallel pushTasks
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