# ============================================================
# VPC — dedicated network for the EKS cluster.
# 2 public subnets (for the LoadBalancer) + 2 private subnets
# (for worker nodes). Single NAT gateway to keep egress cost low.
# ============================================================

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.cluster_name}-vpc"
  cidr = "10.0.0.0/16"

  # Use the first two available AZs discovered in main.tf
  azs             = slice(data.aws_availability_zones.available.names, 0, 2)
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  # Single NAT gateway: worker nodes in private subnets can reach the internet
  # (to pull images from ECR and talk to the EKS API) at minimum cost.
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  # These subnet tags are required by EKS for subnet auto-discovery when
  # creating LoadBalancer services (the frontend will use one).
  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
}
