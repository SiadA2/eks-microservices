output "role_name" {
  description = "IAM role name"
  value       = try(aws_iam_role.this[0].name, null)
}

output "role_arn" {
  description = "IAM role ARN"
  value       = try(aws_iam_role.this[0].arn, null)
}

output "role_id" {
  description = "IAM role ID"
  value       = try(aws_iam_role.this[0].id, null)
}

output "instance_profile_name" {
  description = "IAM instance profile name"
  value       = try(aws_iam_instance_profile.this[0].name, null)
}

output "instance_profile_arn" {
  description = "IAM instance profile ARN"
  value       = try(aws_iam_instance_profile.this[0].arn, null)
}

output "route53_irsa_role_arns" {
  description = "Route 53 IRSA role ARNs keyed by service account identifier"
  value       = { for key, role in aws_iam_role.route53_irsa : key => role.arn }
}

output "route53_dns_management_policy_arn" {
  description = "ARN of the Route 53 DNS management policy"
  value       = try(aws_iam_policy.route53_dns_management[0].arn, null)
}
