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

stage('Initialize') {
  steps {
    script {
      def resolvedRepoRoot = repoRoot(this)
      env.REPO_ROOT = resolvedRepoRoot ?: '.'

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

      // Normalize paths when repository root is shopNow/
      if (env.REPO_ROOT != '.') {
        changedFiles = changedFiles.collect { file ->
          file.startsWith("${env.REPO_ROOT}/") ? file.substring(env.REPO_ROOT.length() + 1) : file
        }
      }

      // Safety net to avoid false no-op
      if (!changedFiles || changedFiles.isEmpty()) {
        echo 'Change detection returned no files; forcing all services to build.'
        changedFiles = ['frontend/', 'admin/', 'backend/']
      }

      env.CHANGESET = changedFiles.take(100).join('\n')

      env.BUILD_FRONTEND = changeMatches(changedFiles, ['frontend/']).toString()
      env.BUILD_ADMIN = changeMatches(changedFiles, ['admin/']).toString()
      env.BUILD_BACKEND = changeMatches(changedFiles, ['backend/']).toString()

      echo "Repository root: ${env.REPO_ROOT}"
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
            sh '''
              docker build \
                --tag shopnow-frontend:${IMAGE_TAG} \
                --tag ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_PREFIX}/frontend:${IMAGE_TAG} \
                --build-arg USER_NAME=${USER_NAME} .
            '''
          }
        }
      }

      if (env.BUILD_ADMIN == 'true') {
        buildTasks.admin = {
          dir(serviceDir(env.REPO_ROOT, 'admin')) {
            sh '''
              docker build \
                --tag shopnow-admin:${IMAGE_TAG} \
                --tag ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_PREFIX}/admin:${IMAGE_TAG} \
                --build-arg USER_NAME=${USER_NAME} .
            '''
          }
        }
      }

      if (env.BUILD_BACKEND == 'true') {
        buildTasks.backend = {
          dir(serviceDir(env.REPO_ROOT, 'backend')) {
            sh '''
              docker build \
                --tag shopnow-backend:${IMAGE_TAG} \
                --tag ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_PREFIX}/backend:${IMAGE_TAG} .
            '''
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
          sh 'docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_PREFIX}/frontend:${IMAGE_TAG}'
        }
      }

      if (env.BUILD_ADMIN == 'true') {
        pushTasks.admin = {
          sh 'docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_PREFIX}/admin:${IMAGE_TAG}'
        }
      }

      if (env.BUILD_BACKEND == 'true') {
        pushTasks.backend = {
          sh 'docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_PREFIX}/backend:${IMAGE_TAG}'
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