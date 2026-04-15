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
  default     = "prod"
}

variable "tags" {
  description = "Additional tags to merge with the default environment tags"
  type        = map(string)
  default     = {}
}
