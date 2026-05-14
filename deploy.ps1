# ============================================================
# deploy.ps1 — Manual deployment script
# ============================================================
# Use this after "terraform apply" to build images and deploy
# the app to EKS without needing a git push.
#
# Usage:
#   .\deploy.ps1 -JwtSecret "mysecret" -MongoUsername "admin" -MongoPassword "pass123"
#
# Or set environment variables first, then run without args:
#   $env:JWT_SECRET      = "mysecret"
#   $env:MONGO_USERNAME  = "admin"
#   $env:MONGO_PASSWORD  = "pass123"
#   .\deploy.ps1
# ============================================================

param(
    [string]$JwtSecret     = $env:JWT_SECRET,
    [string]$MongoUsername = $env:MONGO_USERNAME,
    [string]$MongoPassword = $env:MONGO_PASSWORD,
    # Default tag: timestamp so each deploy gets a unique image
    [string]$ImageTag      = (Get-Date -Format "yyyyMMdd-HHmmss")
)

# ── Config ────────────────────────────────────────────────────
$AWS_REGION     = "us-east-1"
$AWS_ACCOUNT_ID = "071179620185"
$CLUSTER_NAME   = "chatapp"
$ECR_BACKEND    = "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/chatapp-backend"
$ECR_FRONTEND   = "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/chatapp-frontend"

# ── Helpers ───────────────────────────────────────────────────
function Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Ok($msg)   { Write-Host "    OK: $msg" -ForegroundColor Green }
function Fail($msg) { Write-Host "`nERROR: $msg" -ForegroundColor Red; exit 1 }

function Apply-Manifest($path) {
    $content = Get-Content $path -Raw
    $content = $content.Replace('${IMAGE_TAG}',      $ImageTag)
    $content = $content.Replace('${JWT_SECRET}',     $JwtSecret)
    $content = $content.Replace('${MONGO_USERNAME}', $MongoUsername)
    $content = $content.Replace('${MONGO_PASSWORD}', $MongoPassword)
    $content | kubectl apply -f -
    if ($LASTEXITCODE -ne 0) { Fail "kubectl apply failed for $path" }
}

# ── Validate inputs ───────────────────────────────────────────
Step "Checking required secrets"
if (-not $JwtSecret)     { Fail "JWT_SECRET is required. Pass -JwtSecret or set `$env:JWT_SECRET" }
if (-not $MongoUsername) { Fail "MONGO_USERNAME is required. Pass -MongoUsername or set `$env:MONGO_USERNAME" }
if (-not $MongoPassword) { Fail "MONGO_PASSWORD is required. Pass -MongoPassword or set `$env:MONGO_PASSWORD" }
Ok "Secrets present. Image tag: $ImageTag"

# ── Configure kubectl ─────────────────────────────────────────
Step "Configuring kubectl for cluster '$CLUSTER_NAME'"
aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME
if ($LASTEXITCODE -ne 0) { Fail "Failed to update kubeconfig" }
Ok "kubeconfig updated"

# ── ECR login ─────────────────────────────────────────────────
Step "Logging in to ECR"
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"
if ($LASTEXITCODE -ne 0) { Fail "ECR login failed" }
Ok "Docker logged in to ECR"

# ── Build and push backend ────────────────────────────────────
Step "Building backend image"
docker build -t "${ECR_BACKEND}:${ImageTag}" .\backend
if ($LASTEXITCODE -ne 0) { Fail "Backend build failed" }

Step "Pushing backend to ECR"
docker push "${ECR_BACKEND}:${ImageTag}"
if ($LASTEXITCODE -ne 0) { Fail "Backend push failed" }
Ok "Backend pushed"

# ── Build and push frontend ───────────────────────────────────
Step "Building frontend image"
docker build -t "${ECR_FRONTEND}:${ImageTag}" .\frontend
if ($LASTEXITCODE -ne 0) { Fail "Frontend build failed" }

Step "Pushing frontend to ECR"
docker push "${ECR_FRONTEND}:${ImageTag}"
if ($LASTEXITCODE -ne 0) { Fail "Frontend push failed" }
Ok "Frontend pushed"

# ── Apply Kubernetes manifests ────────────────────────────────
Step "Applying Kubernetes manifests"

kubectl apply -f k8s\namespace.yml
if ($LASTEXITCODE -ne 0) { Fail "Failed to apply namespace" }

Apply-Manifest k8s\secrets.yml

kubectl apply -f k8s\mongodb-pvc.yml
if ($LASTEXITCODE -ne 0) { Fail "Failed to apply mongodb-pvc" }

kubectl apply -f k8s\mongodb-deployment.yml
if ($LASTEXITCODE -ne 0) { Fail "Failed to apply mongodb-deployment" }

kubectl apply -f k8s\mongodb-service.yml
if ($LASTEXITCODE -ne 0) { Fail "Failed to apply mongodb-service" }

Apply-Manifest k8s\backend-deployment.yml

kubectl apply -f k8s\backend-service.yml
if ($LASTEXITCODE -ne 0) { Fail "Failed to apply backend-service" }

Apply-Manifest k8s\frontend-deployment.yml

kubectl apply -f k8s\frontend-service.yml
if ($LASTEXITCODE -ne 0) { Fail "Failed to apply frontend-service" }

Ok "All manifests applied"

# ── Wait for rollouts ─────────────────────────────────────────
Step "Waiting for backend rollout (up to 5 min)"
kubectl rollout status deployment/backend-deployment -n chatapp --timeout=300s
if ($LASTEXITCODE -ne 0) { Fail "Backend rollout did not complete" }

Step "Waiting for frontend rollout (up to 5 min)"
kubectl rollout status deployment/frontend-deployment -n chatapp --timeout=300s
if ($LASTEXITCODE -ne 0) { Fail "Frontend rollout did not complete" }

# ── Print URL ─────────────────────────────────────────────────
Step "Getting frontend URL (may take 1-2 min for LoadBalancer to provision)"
$attempts = 0
$url = ""
while (-not $url -and $attempts -lt 20) {
    Start-Sleep -Seconds 10
    $url = kubectl get svc frontend-service -n chatapp -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>$null
    $attempts++
}

Write-Host ""
if ($url) {
    Write-Host "========================================" -ForegroundColor Green
    Write-Host " App is live at: http://$url" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
} else {
    Write-Host "LoadBalancer URL not ready yet. Run this to check:" -ForegroundColor Yellow
    Write-Host "  kubectl get svc -n chatapp" -ForegroundColor Yellow
}
