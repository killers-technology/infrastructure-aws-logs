# Regional definitions ------------------------------------------------------------------------------

output "bucket_name" {
  description = "Central log bucket of this region. infrastructure-aws-security sets it as the organization trail's destination."
  value       = one(aws_s3_bucket.logs[*].id)
}

output "bucket_arn" {
  description = "ARN of the central log bucket. The other region's definition uses it as its replication destination."
  value       = one(aws_s3_bucket.logs[*].arn)
}

output "kms_key_arn" {
  description = "ARN of the key that encrypts the bucket. Used by the organization trail and as the other region's replica key."
  value       = one(aws_kms_key.logs[*].arn)
}

# Global definition ---------------------------------------------------------------------------------

output "replication_role_arn" {
  description = "Role S3 assumes to replicate each archive bucket into the other. Both regional definitions set it as replication.role_arn."
  value       = one(aws_iam_role.replication[*].arn)
}
