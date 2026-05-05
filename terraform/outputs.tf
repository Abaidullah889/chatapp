# ============================================================
# Outputs
# ============================================================
# These values are needed in later steps:
#   - configure_kubectl : run this after apply to connect kubectl
#   - ecr_*_url         : used in k8s manifests (Step 4) and CI/CD (Step 5)
# ============================================================

output "cluster_name" {
  description = "EKS cluster name — used in kubectl and CI/CD commands"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint"
  value       = module.eks.cluster_endpoint
}

output "configure_kubectl" {
  description = "Run this command once after apply to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

output "ecr_backend_url" {
  description = "ECR repository URL for the backend image (use in k8s manifests and CI/CD)"
  value       = aws_ecr_repository.backend.repository_url
}

output "ecr_frontend_url" {
  description = "ECR repository URL for the frontend image (use in k8s manifests and CI/CD)"
  value       = aws_ecr_repository.frontend.repository_url
}

output "aws_region" {
  description = "AWS region — needed for the ECR login command in CI/CD"
  value       = var.aws_region
}
