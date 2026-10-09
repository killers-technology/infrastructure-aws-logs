# IAM is global: the replication role is created once, by definitions/prod/global (applied from
# us-east-1, before the regional definitions). One role serves both directions, because each archive
# bucket is the other's replication destination. Its permissions are built from the bucket naming
# convention in main.tf; this definition never reads the regional states, and they receive the role
# ARN by value (replication.role_arn).

locals {
  archive_bucket_arns = { for region, name in local.bucket_names : region => "arn:aws:s3:::${name}" }
}

resource "aws_iam_role" "replication" {
  count = local.global ? 1 : 0

  name               = local.replication_role_name
  description        = "S3 replication between the log-archive buckets of us-east-1 and us-west-2"
  assume_role_policy = data.aws_iam_policy_document.replication_assume[0].json
}

data "aws_iam_policy_document" "replication_assume" {
  count = local.global ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    # Only S3 acting for this account's buckets.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.account_id]
    }
  }
}

resource "aws_iam_role_policy" "replication" {
  count = local.global ? 1 : 0

  name   = "replicate-log-archive"
  role   = aws_iam_role.replication[0].id
  policy = data.aws_iam_policy_document.replication[0].json
}

data "aws_iam_policy_document" "replication" {
  count = local.global ? 1 : 0

  # Source side: read the replication rule, then each object version with its tags, Object Lock
  # retention and legal hold, so the replica stays locked as long as the original.
  statement {
    sid       = "SourceBuckets"
    actions   = ["s3:GetReplicationConfiguration", "s3:ListBucket"]
    resources = values(local.archive_bucket_arns)
  }

  statement {
    sid = "SourceObjects"
    actions = [
      "s3:GetObjectVersionForReplication",
      "s3:GetObjectVersionAcl",
      "s3:GetObjectVersionTagging",
      "s3:GetObjectRetention",
      "s3:GetObjectLegalHold",
    ]
    resources = [for arn in values(local.archive_bucket_arns) : "${arn}/*"]
  }

  # Destination side: write the replicas into the other bucket.
  statement {
    sid       = "DestinationObjects"
    actions   = ["s3:ReplicateObject", "s3:ReplicateDelete", "s3:ReplicateTags"]
    resources = [for arn in values(local.archive_bucket_arns) : "${arn}/*"]
  }

  # Each region's archive key: decrypt the source objects, encrypt the replicas. The key IDs are not
  # known here, so each statement allows this account's keys of one region, but only when S3 in that
  # region calls KMS for that region's archive bucket.
  dynamic "statement" {
    for_each = local.archive_bucket_arns

    content {
      sid       = "ArchiveKey${join("", [for part in split("-", statement.key) : title(part)])}"
      actions   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey"]
      resources = ["arn:aws:kms:${statement.key}:${var.account_id}:key/*"]

      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = ["s3.${statement.key}.amazonaws.com"]
      }

      # With an S3 Bucket Key (bucket.tf) the encryption context is the bucket ARN; without one it is
      # the object ARN. Both are allowed.
      condition {
        test     = "StringLike"
        variable = "kms:EncryptionContext:aws:s3:arn"
        values   = [statement.value, "${statement.value}/*"]
      }
    }
  }
}
