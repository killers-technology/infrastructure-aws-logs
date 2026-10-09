account_id  = "352243449836" # log-archive
region      = "us-east-1"
environment = "prod"

# S3 bucket names are global: the archive buckets carry the organization\'s prefix.
bucket_name_prefix = "killers-technology-"
scope              = "regional"

organization_id = "o-r5s2qddqgq"

# Created by infrastructure-aws-security from Security Tooling (CloudTrail delegated administrator),
# but organization trails are owned by the management account, so its ID is in the ARN.
organization_trail_arn = "arn:aws:cloudtrail:us-east-1:301697000338:trail/organization-trail"

# COMPLIANCE: nobody, root included, can delete a log version or shorten its retention for a year.
object_lock_mode           = "COMPLIANCE"
object_lock_retention_days = 1 # e2e: shortest retention

transition_to_glacier_days         = 90
expiration_days                    = 2557 # 7 years
noncurrent_version_expiration_days = 30

# DR copy into us-west-2, by value:
# - role: output replication_role_arn of definitions/prod/global, applied before both regions;
# - bucket and key: outputs bucket_arn and kms_key_arn of definitions/prod/us-west-2, applied first.
# Set to null until that side exists.
replication = {
  role_arn                = "arn:aws:iam::352243449836:role/log-archive-replication"
  destination_bucket_arn  = "arn:aws:s3:::killers-technology-log-archive-us-west-2"
  destination_kms_key_arn = "arn:aws:kms:us-west-2:352243449836:key/30420a0f-ca14-41f9-951d-6fb7566abf50"
}
