variable "aws_region" {
  description = "AWS region for the environment"
  type        = string
  default     = "eu-west-2"
}

variable "project_name" {
  description = "Project name used in tags and resource naming"
  type        = string
  default     = "eks-microservices"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "tags" {
  description = "Additional tags to merge with the default environment tags"
  type        = map(string)
  default     = {}
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
}

variable "azs" {
  description = "Availability zones for the environment"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDR blocks"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDR blocks"
  type        = list(string)
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.33"
}

variable "instance_types" {
  description = "EC2 instance types for the EKS managed node group"
  type        = list(string)
}

variable "min_size" {
  description = "Minimum size of the EKS managed node group"
  type        = number
}

variable "max_size" {
  description = "Maximum size of the EKS managed node group"
  type        = number
}

variable "desired_size" {
  description = "Desired size of the EKS managed node group"
  type        = number
}
