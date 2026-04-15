locals {
  service_names = toset([
    "api-gateway",
    "dashboard-api",
    "inventory-service",
    "notification-service",
    "order-service",
    "payment-service",
    "scheduler",
    "shipping-service",
    "worker",
  ])
}

module "vpc" {
  source = "../../modules/vpc"

  cluster_name         = var.cluster_name
  vpc_cidr             = var.vpc_cidr
  azs                  = var.azs
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  tags                 = local.tags
}

module "eks" {
  source = "../../modules/eks"

  cluster_name                    = var.cluster_name
  kubernetes_version              = var.kubernetes_version
  vpc_id                          = module.vpc.vpc_id
  subnet_ids                      = module.vpc.private_subnet_ids
  control_plane_subnet_ids        = module.vpc.private_subnet_ids
  instance_types                  = var.instance_types
  min_size                        = var.min_size
  max_size                        = var.max_size
  desired_size                    = var.desired_size
  load_balancer_security_group_id = module.vpc.load_balancer_security_group_id
  tags                            = local.tags
}

module "ecr" {
  for_each = local.service_names
  source   = "../../modules/ecr"

  repo_name = "${var.environment}-${each.key}"
}
