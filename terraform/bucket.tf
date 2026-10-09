locals {
  # The organization trail is owned by the management account, whose ID is part of the trail ARN.
  # null in the global definition, which has no trail ARN.
  management_account_id = try(split(":", var.organization_trail_arn)[4], null)
}

resource "aws_s3_bucket" "logs" {
  count = local.regional ? 1 : 0

  bucket = local.bucket_name

  # Object Lock can only be switched on here, at creation. With COMPLIANCE mode the bucket cannot be
  # deleted (not even by root) until the last locked object version reaches its retention date.
  object_lock_enabled = true
}

resource "aws_s3_bucket_versioning" "logs" {
  count = local.regional ? 1 : 0

  bucket = aws_s3_bucket.logs[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_object_lock_configuration" "logs" {
  count = local.regional ? 1 : 0

  bucket = aws_s3_bucket.logs[0].id

  rule {
    default_retention {
      mode = var.object_lock_mode
      days = var.object_lock_retention_days
    }
  }

  depends_on = [aws_s3_bucket_versioning.logs]
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  count = local.regional ? 1 : 0

  bucket = aws_s3_bucket.logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.logs[0].arn
    }

    # One data key per bucket instead of one KMS call per object: log delivery writes a lot of small files.
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "logs" {
  count = local.regional ? 1 : 0

  bucket = aws_s3_bucket.logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ACLs are disabled: every object belongs to this account, whoever delivered it.
resource "aws_s3_bucket_ownership_controls" "logs" {
  count = local.regional ? 1 : 0

  bucket = aws_s3_bucket.logs[0].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  count = local.regional ? 1 : 0

  bucket = aws_s3_bucket.logs[0].id

  # Objects under 128 KB are not transitioned (the S3 default): for tiny log files the per-object
  # transition cost outweighs the storage saving.
  rule {
    id     = "archive-then-expire"
    status = "Enabled"

    filter {}

    transition {
      days          = var.transition_to_glacier_days
      storage_class = "GLACIER"
    }

    # On a versioned bucket this only adds a delete marker; the version becomes noncurrent.
    expiration {
      days = var.expiration_days
    }

    # Lifecycle cannot remove a version that is still under Object Lock retention.
    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_expiration_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.logs]
}

resource "aws_s3_bucket_policy" "logs" {
  count = local.regional ? 1 : 0

  bucket = aws_s3_bucket.logs[0].id
  policy = data.aws_iam_policy_document.bucket[0].json

  # The public access block must exist first, or a policy change can race it.
  depends_on = [aws_s3_bucket_public_access_block.logs]
}

data "aws_iam_policy_document" "bucket" {
  count = local.regional ? 1 : 0

  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.logs[0].arn,
      "${aws_s3_bucket.logs[0].arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  # CloudTrail organization trail. aws:SourceArn pins every statement to that one trail.
  statement {
    sid       = "CloudTrailAclCheck"
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.logs[0].arn]

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

  statement {
    sid     = "CloudTrailWrite"
    actions = ["s3:PutObject"]
    resources = [
      # Every member account's events, under the organization ID.
      "${aws_s3_bucket.logs[0].arn}/AWSLogs/${var.organization_id}/*",
      # The owner account's own path, used if the trail is ever converted to an account trail.
      "${aws_s3_bucket.logs[0].arn}/AWSLogs/${local.management_account_id}/*",
    ]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [var.organization_trail_arn]
    }
  }

  # AWS Config delivery channels from any account in the organization.
  statement {
    sid       = "ConfigBucketChecks"
    actions   = ["s3:GetBucketAcl", "s3:ListBucket"]
    resources = [aws_s3_bucket.logs[0].arn]

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

  statement {
    sid       = "ConfigWrite"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.logs[0].arn}/AWSLogs/*/Config/*"]

    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceOrgID"
      values   = [var.organization_id]
    }
  }
}
