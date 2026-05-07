# ============================================================
# Input variables — all have sensible defaults for this demo.
# Override via -var flags or terraform.tfvars (not committed).
# ============================================================

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Name prefix for the EKS cluster and all related resources"
  type        = string
  default     = "chatapp"
}

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS control plane"
  type        = string
  default     = "1.30"
}

variable "node_instance_type" {
  description = "EC2 instance type for EKS worker nodes"
  type        = string
  default     = "t3.small"
}

variable "node_desired_count" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 2
}

variable "node_min_count" {
  description = "Minimum number of worker nodes (keep at 1 so the cluster stays usable)"
  type        = number
  default     = 1
}

variable "node_max_count" {
  description = "Maximum number of worker nodes (capped at 2 for cost control)"
  type        = number
  default     = 2
}
