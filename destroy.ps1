# ============================================================
# destroy.ps1 — Safe infrastructure teardown script
# ============================================================
# Run this INSTEAD of "terraform destroy" directly.
# It cleans up Kubernetes-managed AWS resources first so that
# terraform destroy does not get stuck on dependency violations.
#
# Usage:
#   .\destroy.ps1
# ============================================================

# ── Helpers ───────────────────────────────────────────────────
function Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Ok($msg)   { Write-Host "    OK: $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "    WARN: $msg" -ForegroundColor Yellow }

# ── Config ────────────────────────────────────────────────────
$AWS_REGION    = "us-east-1"
$CLUSTER_NAME  = "chatapp"
$NAMESPACE     = "chatapp"
$ECR_REPOS     = @("chatapp-backend", "chatapp-frontend")

# ── Step 1: Update kubeconfig ─────────────────────────────────
Step "Connecting kubectl to cluster '$CLUSTER_NAME'"
aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Warn "Could not connect kubectl — cluster may already be gone. Continuing..."
} else {
    Ok "kubectl connected"

    # ── Step 2: Delete LoadBalancer service via kubectl ───────
    Step "Deleting frontend LoadBalancer service (triggers ELB deletion)"
    kubectl delete svc frontend-service -n $NAMESPACE 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Ok "frontend-service deleted"
    } else {
        Warn "frontend-service not found — may already be deleted"
    }

    # ── Step 3: Delete MongoDB EBS volumes ────────────────────
    Step "Finding EBS volumes created by Kubernetes PVCs"
    $volumeIds = aws ec2 describe-volumes `
        --filters "Name=tag:kubernetes.io/created-for/pvc/namespace,Values=$NAMESPACE" `
        --query "Volumes[*].VolumeId" `
        --output text 2>&1

    if ($volumeIds -and $volumeIds.Trim() -ne "") {
        foreach ($volId in $volumeIds.Split()) {
            if ($volId.Trim()) {
                Write-Host "    Deleting volume: $volId" -ForegroundColor Yellow
                aws ec2 delete-volume --volume-id $volId 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) { Ok "Deleted $volId" }
                else { Warn "Could not delete $volId — skipping" }
            }
        }
    } else {
        Ok "No PVC-created EBS volumes found"
    }
}

# ── Step 4: Wait for ELB to be removed by AWS ────────────────
Step "Waiting for AWS to remove the ELB (up to 90 seconds)"
$attempts = 0
while ($attempts -lt 9) {
    $elbs = aws elb describe-load-balancers `
        --query "LoadBalancerDescriptions[*].LoadBalancerName" `
        --output text 2>&1
    if (-not $elbs -or $elbs.Trim() -eq "") {
        Ok "ELB removed"
        break
    }
    # If still there after waiting, force delete it
    if ($attempts -eq 5) {
        Warn "ELB still exists after 50s — force deleting via AWS CLI"
        foreach ($elbName in $elbs.Split()) {
            if ($elbName.Trim()) {
                aws elb delete-load-balancer --load-balancer-name $elbName.Trim() 2>&1 | Out-Null
                Ok "Force deleted ELB: $elbName"
            }
        }
    }
    Start-Sleep -Seconds 10
    $attempts++
}

# ── Step 5: Clear ECR images ──────────────────────────────────
Step "Clearing ECR repositories (so terraform can delete them)"
foreach ($repo in $ECR_REPOS) {
    # Get all image tags in the repo
    $tags = aws ecr list-images --repository-name $repo `
        --query "imageIds[*].imageTag" --output text 2>&1
    if ($LASTEXITCODE -ne 0 -or -not $tags -or $tags.Trim() -eq "") {
        Ok "$repo is already empty or does not exist"
        continue
    }
    # Delete each image individually by tag
    foreach ($tag in $tags.Split()) {
        if ($tag.Trim() -and $tag.Trim() -ne "None") {
            aws ecr batch-delete-image --repository-name $repo `
                --image-ids "imageTag=$($tag.Trim())" 2>&1 | Out-Null
            Ok "Deleted $repo`:$tag"
        }
    }
    # Also delete any untagged images
    $digests = aws ecr list-images --repository-name $repo `
        --filter "tagStatus=UNTAGGED" `
        --query "imageIds[*].imageDigest" --output text 2>&1
    foreach ($digest in $digests.Split()) {
        if ($digest.Trim() -and $digest.Trim() -ne "None") {
            aws ecr batch-delete-image --repository-name $repo `
                --image-ids "imageDigest=$($digest.Trim())" 2>&1 | Out-Null
            Ok "Deleted untagged image from $repo"
        }
    }
}

# ── Step 6: Terraform destroy ─────────────────────────────────
Step "Running terraform destroy"
Set-Location D:\Devops_Course\Assignment\chatapp\terraform
C:\terraform\terraform.exe destroy -auto-approve

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host " Infrastructure fully destroyed" -ForegroundColor Green
    Write-Host " No AWS resources are running" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Red
    Write-Host " terraform destroy reported errors" -ForegroundColor Red
    Write-Host " Check output above for details" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
}
