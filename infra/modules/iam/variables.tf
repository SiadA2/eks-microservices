variable "name" {
  description = "IAM role name"
  type        = string
  default     = null
}

variable "create_role" {
  description = "Whether to create the general-purpose IAM role"
  type        = bool
  default     = true
}

variable "description" {
  description = "IAM role description"
  type        = string
  default     = "Permissive IAM role for rapid development"
}

variable "path" {
  description = "IAM path for the role"
  type        = string
  default     = "/"
}

variable "max_session_duration" {
  description = "Maximum session duration in seconds"
  type        = number
  default     = 3600
}

variable "trusted_service_principals" {
  description = "AWS service principals allowed to assume this role"
  type        = list(string)
  default     = ["ec2.amazonaws.com", "pods.eks.amazonaws.com"]
}

variable "trusted_aws_principals" {
  description = "AWS principal ARNs allowed to assume this role"
  type        = list(string)
  default     = []
}

variable "create_instance_profile" {
  description = "Whether to create an instance profile for EC2 use"
  type        = bool
  default     = false
}

variable "instance_profile_name" {
  description = "Optional custom name for the instance profile"
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags to apply to IAM resources"
  type        = map(string)
  default     = {}
}

variable "create_route53_irsa" {
  description = "Whether to create Route 53 IRSA roles for Kubernetes service accounts"
  type        = bool
  default     = false
}

variable "project_name" {
  description = "Project name used in Route 53 IRSA resource names"
  type        = string
  default     = null
}

variable "environment" {
  description = "Environment name used in Route 53 IRSA resource names"
  type        = string
  default     = null
}

variable "cluster_name" {
  description = "EKS cluster name used to discover the OIDC issuer for IRSA"
  type        = string
  default     = null
}

variable "domain_name" {
  description = "Domain name for the Route 53 hosted zone"
  type        = string
  default     = null
}

variable "hosted_zone_id" {
  description = "ID of the Route 53 hosted zone"
  type        = string
  default     = null
}

variable "route53_irsa_subjects" {
  description = "Kubernetes service account subjects allowed to assume Route 53 IRSA roles"
  type        = map(string)
  default = {
    cert_manager = "system:serviceaccount:cert-manager:cert-manager"
    external_dns = "system:serviceaccount:external-dns:external-dns"
  }
}
