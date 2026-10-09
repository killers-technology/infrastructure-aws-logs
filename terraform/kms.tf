resource "aws_kms_key" "logs" {
  count = local.regional ? 1 : 0

  description             = "Encrypts the central log archive in ${var.region}"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.kms[0].json
}

resource "aws_kms_alias" "logs" {
  count = local.regional ? 1 : 0

  name          = "alias/${local.bucket_name}"
  target_key_id = aws_kms_key.logs[0].key_id
}

data "aws_iam_policy_document" "kms" {
  count = local.regional ? 1 : 0

  # Hands key administration to IAM in this account. Without it the key can become unmanageable.
  # The replication role (global.tf) gets its kms:Decrypt / kms:Encrypt through its own IAM policy via this statement.
  statement {
    sid       = "AccountAdministration"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.account_id}:root"]
    }
  }

  # Only the organization trail may use the key, and only for its own log files.
  statement {
    sid       = "CloudTrailEncrypt"
    actions   = ["kms:GenerateDataKey*"]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [var.organization_trail_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "kms:EncryptionContext:aws:cloudtrail:arn"
      values   = [var.organization_trail_arn]
    }
  }

  statement {
    sid       = "CloudTrailDescribeAndDecrypt"
    actions   = ["kms:DescribeKey", "kms:Decrypt"]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [var.organization_trail_arn]
    }
  }

  # AWS Config delivery channels in every member account write through the service principal.
  statement {
    sid       = "ConfigEncrypt"
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceOrgID"
      values   = [var.organization_id]
    }
  }

  # Readers can decrypt only if they belong to the organization. This statement alone does not
  # grant read access: they still need s3:GetObject from the bucket owner.
  statement {
    sid       = "OrganizationReadersDecrypt"
    actions   = ["kms:Decrypt", "kms:DescribeKey"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalOrgID"
      values   = [var.organization_id]
    }
  }
}
