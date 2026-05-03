output "cert_manager_route53_role_arn" {
  description = "IAM role ARN used by cert-manager for Route 53 DNS-01 challenges"
  value       = module.iam.route53_irsa_role_arns["cert_manager"]
}

output "external_dns_route53_role_arn" {
  description = "IAM role ARN used by external-dns for Route 53 record management"
  value       = module.iam.route53_irsa_role_arns["external_dns"]
}
