moved {
  from = aws_iam_policy.route53_dns_management
  to   = module.iam.aws_iam_policy.route53_dns_management[0]
}

moved {
  from = aws_iam_role.route53_irsa["cert_manager"]
  to   = module.iam.aws_iam_role.route53_irsa["cert_manager"]
}

moved {
  from = aws_iam_role.route53_irsa["external_dns"]
  to   = module.iam.aws_iam_role.route53_irsa["external_dns"]
}

moved {
  from = aws_iam_role_policy_attachment.route53_irsa["cert_manager"]
  to   = module.iam.aws_iam_role_policy_attachment.route53_irsa["cert_manager"]
}

moved {
  from = aws_iam_role_policy_attachment.route53_irsa["external_dns"]
  to   = module.iam.aws_iam_role_policy_attachment.route53_irsa["external_dns"]
}
