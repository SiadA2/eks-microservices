data "aws_partition" "current" {}

data "aws_iam_policy_document" "assume_role" {
  dynamic "statement" {
    for_each = length(var.trusted_service_principals) > 0 ? [1] : []

    content {
      effect  = "Allow"
      actions = ["sts:AssumeRole"]

      principals {
        type        = "Service"
        identifiers = var.trusted_service_principals
      }
    }
  }

  dynamic "statement" {
    for_each = length(var.trusted_aws_principals) > 0 ? [1] : []

    content {
      effect  = "Allow"
      actions = ["sts:AssumeRole"]

      principals {
        type        = "AWS"
        identifiers = var.trusted_aws_principals
      }
    }
  }
}

resource "aws_iam_role" "this" {
  count = var.create_role ? 1 : 0

  name                 = var.name
  description          = var.description
  path                 = var.path
  assume_role_policy   = data.aws_iam_policy_document.assume_role.json
  max_session_duration = var.max_session_duration

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "administrator_access" {
  count = var.create_role ? 1 : 0

  role       = aws_iam_role.this[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_instance_profile" "this" {
  count = var.create_role && var.create_instance_profile ? 1 : 0

  name = var.instance_profile_name != null ? var.instance_profile_name : var.name
  role = aws_iam_role.this[0].name

  tags = var.tags
}

data "aws_eks_cluster" "this" {
  count = var.create_route53_irsa ? 1 : 0

  name = var.cluster_name
}

data "aws_iam_openid_connect_provider" "eks" {
  count = var.create_route53_irsa ? 1 : 0

  url = data.aws_eks_cluster.this[0].identity[0].oidc[0].issuer
}

locals {
  oidc_provider_host = var.create_route53_irsa ? replace(data.aws_eks_cluster.this[0].identity[0].oidc[0].issuer, "https://", "") : null
}

data "aws_iam_policy_document" "route53_dns_management" {
  count = var.create_route53_irsa ? 1 : 0

  statement {
    sid = "AllowHostedZoneChanges"

    actions = [
      "route53:ChangeResourceRecordSets",
      "route53:ListResourceRecordSets",
    ]

    resources = [
      "arn:${data.aws_partition.current.partition}:route53:::hostedzone/${var.hosted_zone_id}",
    ]
  }

  statement {
    sid = "AllowRoute53Discovery"

    actions = [
      "route53:GetChange",
      "route53:ListHostedZones",
      "route53:ListHostedZonesByName",
    ]

    resources = ["*"]
  }
}

resource "aws_iam_policy" "route53_dns_management" {
  count = var.create_route53_irsa ? 1 : 0

  name        = "${var.environment}-${var.project_name}-route53-dns-management"
  description = "Allow Kubernetes DNS controllers to manage records in ${var.domain_name}"
  policy      = data.aws_iam_policy_document.route53_dns_management[0].json

  tags = var.tags
}

data "aws_iam_policy_document" "route53_irsa_assume_role" {
  for_each = var.create_route53_irsa ? var.route53_irsa_subjects : {}

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.eks[0].arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_host}:sub"
      values   = [each.value]
    }
  }
}

resource "aws_iam_role" "route53_irsa" {
  for_each = var.create_route53_irsa ? var.route53_irsa_subjects : {}

  name               = "${var.environment}-${var.project_name}-${replace(each.key, "_", "-")}-route53"
  assume_role_policy = data.aws_iam_policy_document.route53_irsa_assume_role[each.key].json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "route53_irsa" {
  for_each = aws_iam_role.route53_irsa

  role       = each.value.name
  policy_arn = aws_iam_policy.route53_dns_management[0].arn
}
