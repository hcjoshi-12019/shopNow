# Pull Request Challenges and Troubleshooting Guide

## Purpose

This document records the challenges encountered while creating and validating the pull request from `feature/shopnow-capston-project-v1` to `main`:

- Pull request: <https://github.com/harishmsgit/shopNow/pull/1>
- Source branch: `feature/shopnow-capston-project-v1`
- Target branch: `main`

It also provides reusable diagnostic and recovery steps for future pull requests.

## 1. GitHub rejected the pull request

### Error

```text
GraphQL: The feature/shopnow-capston-project-v1 branch has no history in common with main
```

### Cause

The remote `main` branch had been force-pushed and replaced with a new root history. The feature branch still contained the original repository history. Although the files belonged to the same project, GitHub could not calculate a normal pull-request comparison because the remote branches had no common ancestor.

The local remote-tracking reference was initially stale, which made the local branches appear related until the repository was fetched again.

### Diagnosis

```bash
git fetch origin --prune
git merge-base origin/main origin/feature/shopnow-capston-project-v1
git log --oneline --graph --decorate --all -n 25
```

An empty result from `git merge-base` confirms that the two remote branches do not share an ancestor.

### Resolution used

The histories were connected with a merge commit while preserving the feature branch's current file tree:

```bash
git switch feature/shopnow-capston-project-v1
git merge --strategy=ours --allow-unrelated-histories origin/main \
  -m "chore: connect feature history to rewritten main"
git push origin feature/shopnow-capston-project-v1
```

After this commit was pushed, GitHub accepted the pull request and reported it as mergeable.

> The `ours` merge strategy deliberately preserves the current branch tree and only connects the histories. It should be used only after comparing both branches and confirming that this is the intended result.

### Prevention

- Avoid force-pushing or recreating shared branches such as `main`.
- Protect `main` and disable force pushes in the GitHub branch protection settings.
- Run `git fetch origin --prune` before comparing branches.
- Create feature branches from the latest remote `main`:

  ```bash
  git switch main
  git pull --ff-only origin main
  git switch -c feature/<name>
  ```

## 2. GitHub Actions Docker check failed

### Failed check

```text
docker-build / Smoke test frontend image
```

### Error

```text
nginx: [emerg] host not found in upstream "backend-service"
in /etc/nginx/conf.d/default.conf:23
```

### Cause

The frontend and admin Nginx configurations proxy API traffic to the Kubernetes service name `backend-service`. The GitHub Actions smoke tests started the frontend and admin containers independently, outside Kubernetes, so that DNS name did not exist. Nginx resolved the upstream during startup, failed, and exited before `/health` could respond.

The containers running on the Jenkins host did not help because GitHub Actions uses a separate, temporary `ubuntu-latest` runner.

### Health-only smoke-test fix

Add a temporary hostname mapping to both the frontend and admin `docker run` commands in `.github/workflows/ci.yml`:

```bash
docker run -d \
  --name shopnow-frontend-smoke \
  --add-host backend-service:127.0.0.1 \
  -p 8080:80 \
  "${FRONTEND_IMAGE}:${GITHUB_SHA}"
```

```bash
docker run -d \
  --name shopnow-admin-smoke \
  --add-host backend-service:127.0.0.1 \
  -p 8081:80 \
  "${ADMIN_IMAGE}:${GITHUB_SHA}"
```

This is suitable when the test only calls `/health`. A full API integration test should instead start the backend and all required dependencies on a shared Docker network.

## 3. Docker image tag was invalid locally

### Error

```text
ERROR: failed to build: invalid tag ":": invalid reference format
```

### Cause

The command used GitHub Actions environment variables:

```bash
"${FRONTEND_IMAGE}:${GITHUB_SHA}"
```

GitHub automatically supplies `GITHUB_SHA`, and the workflow defines `FRONTEND_IMAGE`. These variables were empty in the local shell, so Docker received `:` as the image tag.

### Local solution

Use an explicit local tag:

```bash
docker build -t shopnow-frontend:local -f frontend/Dockerfile frontend
```

Alternatively, define the variables first:

```bash
export FRONTEND_IMAGE=shopnow-frontend
export GITHUB_SHA=local
docker build -t "${FRONTEND_IMAGE}:${GITHUB_SHA}" frontend
```

## 4. Dockerfile was not found

### Error

```text
failed to read dockerfile: open Dockerfile: no such file or directory
```

### Cause

The Docker build context did not contain the expected `Dockerfile`. Common reasons include being on the wrong branch, using a stale clone, running the command from the wrong directory, or having a nested project directory.

### Diagnosis and solution

```bash
cd ~/shopNow
git fetch origin
git switch feature/shopnow-capston-project-v1
git pull --ff-only
find . -maxdepth 4 -name Dockerfile -print
```

Build all project images using explicit Dockerfile and context paths:

```bash
docker build -t shopnow-frontend:local -f frontend/Dockerfile frontend
docker build -t shopnow-admin:local -f admin/Dockerfile admin
docker build -t shopnow-backend:local -f backend/Dockerfile backend
```

## 5. Jenkins resumed during an AWS identity check

### Log symptoms

```text
+ aws sts get-caller-identity --region ap-south-1
Resuming build ... after Jenkins restart
Timeout set to expire ...
Ready to run ...
```

### Cause

Jenkins restarted while the shell step was running. The resumed pipeline did not show a successful AWS identity response, indicating that the durable shell step could have been interrupted or orphaned. This was separate from the GitHub Actions PR check.

### Recommended recovery

1. Abort the stalled Jenkins execution.
2. Confirm that the Jenkins agent is online and has an available executor.
3. Confirm that the `awsId` Jenkins credential is valid.
4. Start a fresh build.
5. Add bounded AWS CLI and pipeline timeouts:

```groovy
timeout(time: 1, unit: 'MINUTES') {
  withCredentials([[
    $class: 'AmazonWebServicesCredentialsBinding',
    credentialsId: 'awsId'
  ]]) {
    sh '''
      aws sts get-caller-identity \
        --region "${AWS_REGION}" \
        --cli-connect-timeout 10 \
        --cli-read-timeout 20 \
        --no-cli-pager
    '''
  }
}
```

## 6. Verification checklist

Before merging a future pull request:

```bash
git fetch origin --prune
git status --short --branch
git merge-base origin/main HEAD
git log --oneline origin/main..HEAD
```

Then verify the GitHub checks:

```bash
gh pr checks <PR_NUMBER> --repo harishmsgit/shopNow
gh run view <RUN_ID> --repo harishmsgit/shopNow --log-failed
```

Confirm that:

- The source and target branches share history.
- The feature branch is pushed and clean.
- All Docker images build successfully.
- Frontend and admin Nginx containers can resolve their configured upstream.
- Backend `/api/health` and web `/health` endpoints respond.
- GitHub Actions checks pass.
- Jenkins credentials, agents, and downstream jobs are healthy.


After testing, remove the smoke-test containers:
docker rm -f \
  shopnow-frontend-smoke \
  shopnow-admin-smoke \
  shopnow-backend-smoke