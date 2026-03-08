# ── VPC ───────────────────────────────────────────────────────────────────────
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.8"

  name = "${var.project}-vpc"
  cidr = var.vpc_cidr

  azs             = ["${var.aws_region}a", "${var.aws_region}b", "${var.aws_region}c"]
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets

  enable_nat_gateway     = true
  single_nat_gateway     = false
  one_nat_gateway_per_az = true

  enable_dns_hostnames = true
  enable_dns_support   = true

  # Required tags for EKS load balancers
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"             = "1"
    "kubernetes.io/cluster/${var.project}-cluster" = "shared"
  }
  public_subnet_tags = {
    "kubernetes.io/role/elb"                       = "1"
    "kubernetes.io/cluster/${var.project}-cluster" = "shared"
  }
}

# ── EKS Cluster ───────────────────────────────────────────────────────────────
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.11"

  cluster_name    = "${var.project}-cluster"
  cluster_version = var.eks_cluster_version

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.private_subnets

  # Enable private endpoint (EKS API accessible only within VPC)
  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = true           # restrict with cluster_endpoint_public_access_cidrs in prod

  # Cluster add-ons
  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent    = true
      before_compute = true
      configuration_values = jsonencode({
        env = {
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.ebs_csi_irsa.iam_role_arn
    }
  }

  # Enable IRSA
  enable_irsa = true

  # Enable cluster creator admin
  enable_cluster_creator_admin_permissions = true

  # Node groups
  eks_managed_node_groups = {
    # ── System nodes (monitoring, argocd, istio) ──
    system = {
      name            = "system"
      instance_types  = ["m5.xlarge"]
      min_size        = 2
      max_size        = 4
      desired_size    = 2
      disk_size       = 50
      labels = {
        role = "system"
      }
      taints = [{
        key    = "CriticalAddonsOnly"
        value  = "true"
        effect = "NO_SCHEDULE"
      }]
      update_config = {
        max_unavailable_percentage = 33
      }
    }

    # ── Application nodes (compliance-scanner pods) ──
    app = {
      name           = "app"
      instance_types = var.eks_node_instance_types
      min_size       = var.eks_min_nodes
      max_size       = var.eks_max_nodes
      desired_size   = var.eks_desired_nodes
      disk_size      = 50
      labels = {
        role = "app"
      }
      update_config = {
        max_unavailable_percentage = 25
      }
      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 50
            volume_type           = "gp3"
            encrypted             = true
            delete_on_termination = true
          }
        }
      }
    }
  }

  # Cluster security group — allow Istio
  cluster_security_group_additional_rules = {
    ingress_istio_webhook = {
      description                = "Istio webhook"
      from_port                  = 15017
      to_port                    = 15017
      protocol                   = "tcp"
      type                       = "ingress"
      source_cluster_security_group = true
    }
  }

  # Enable CloudWatch logging for audit trail
  cluster_enabled_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

# ── EBS CSI Driver IRSA ───────────────────────────────────────────────────────
module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.39"

  role_name             = "${var.project}-ebs-csi-role"
  attach_ebs_csi_policy = true
  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

# ── Istio via Helm ────────────────────────────────────────────────────────────
resource "helm_release" "istio_base" {
  name             = "istio-base"
  repository       = "https://istio-release.storage.googleapis.com/charts"
  chart            = "base"
  namespace        = "istio-system"
  create_namespace = true
  version          = "1.21.2"

  depends_on = [module.eks]
}

resource "helm_release" "istiod" {
  name       = "istiod"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "istiod"
  namespace  = "istio-system"
  version    = "1.21.2"

  set {
    name  = "telemetry.enabled"
    value = "true"
  }
  set {
    name  = "global.tracer.zipkin.address"
    value = "otel-collector.monitoring:9411"
  }

  depends_on = [helm_release.istio_base]
}

resource "helm_release" "istio_ingress" {
  name       = "istio-ingress"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "gateway"
  namespace  = "istio-ingress"
  create_namespace = true
  version    = "1.21.2"

  depends_on = [helm_release.istiod]
}

# ── ArgoCD via Helm ───────────────────────────────────────────────────────────
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  version          = "7.1.3"

  values = [
    yamlencode({
      server = {
        ingress = {
          enabled = false    # managed by Istio
        }
      }
      configs = {
        params = {
          "server.insecure" = "true"
        }
      }
    })
  ]

  depends_on = [module.eks]
}
