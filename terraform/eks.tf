# ============================================================
# EKS Cluster
# ============================================================
# Uses the official AWS EKS module. The module creates:
#   - Control plane (managed by AWS, ~$0.10/hr — destroy when not in use)
#   - OIDC provider (needed for IRSA — see ebs_csi_irsa below)
#   - Managed node group (the EC2 instances that run our pods)
#   - Core add-ons: CoreDNS, kube-proxy, VPC CNI, EBS CSI driver
# ============================================================

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.kubernetes_version

  # Public endpoint lets us run kubectl from a laptop without a VPN.
  cluster_endpoint_public_access = true

  # Grant the IAM identity that runs terraform apply cluster-admin access
  # automatically. Without this, the caller can't run kubectl after apply.
  enable_cluster_creator_admin_permissions = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # ── Add-ons ──────────────────────────────────────────────
  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }

    # EBS CSI driver: required so that PersistentVolumeClaims can
    # dynamically provision EBS volumes. Used by MongoDB in k8s/.
    # service_account_role_arn wires it to the IRSA role defined below.
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.ebs_csi_irsa.iam_role_arn
    }
  }

  # ── Managed Node Group ───────────────────────────────────
  eks_managed_node_groups = {
    main = {
      instance_types = [var.node_instance_type]
      min_size       = var.node_min_count
      max_size       = var.node_max_count
      desired_size   = var.node_desired_count

      # AmazonEC2ContainerRegistryReadOnly lets nodes pull images from ECR
      # without needing docker login in every pod.
      iam_role_additional_policies = {
        AmazonEC2ContainerRegistryReadOnly = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
      }
    }
  }
}

# ============================================================
# IRSA role for the EBS CSI driver
# ============================================================
# IRSA gives the EBS CSI controller pod its own IAM role with
# only the permissions it needs (create/attach/detach EBS volumes).
# This is safer than giving those permissions to every pod on the node.
# ============================================================

module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${var.cluster_name}-ebs-csi-driver"

  # Attaches the managed policy AmazonEBSCSIDriverPolicy
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}
