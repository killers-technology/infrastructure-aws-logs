locals {
  global   = var.scope == "global"
  regional = var.scope == "regional"

  # One archive bucket per allowed region, named after it. Each regional definition creates its own;
  # the global definition builds the replication role's permissions from the same names, so it never
  # reads the regional states.
  # Bucket names are global across every AWS account, so they carry the organization's prefix.
  bucket_names = { for region in ["us-east-1", "us-west-2"] : region => "${var.bucket_name_prefix}log-archive-${region}" }
  bucket_name  = local.bucket_names[var.region]

  # Created by the global definition (global.tf). The regional definitions receive its ARN by value,
  # in replication.role_arn.
  replication_role_name = "log-archive-replication"
}
