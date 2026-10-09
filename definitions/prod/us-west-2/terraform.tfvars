account_id  = "352243449836" # log-archive
region      = "us-west-2"
environment = "prod"

# S3 bucket names are global: the archive buckets carry the organization\'s prefix.
bucket_name_prefix = "killers-technology-"
scope              = "regional"

organization_id = "o-r5s2qddqgq"

# The trail is multi-region and delivers to killers-technology-log-archive-us-east-1. This bucket still accepts it,
# so the trail can be repointed here if us-east-1 is lost.
organization_trail_arn = "arn:aws:cloudtrail:us-east-1:301697000338:trail/organization-trail"

object_lock_mode           = "COMPLIANCE"
object_lock_retention_days = 1 # e2e: shortest retention

transition_to_glacier_days         = 90
expiration_days                    = 2557 # 7 years
noncurrent_version_expiration_days = 30

# DR copy back into us-east-1, by value:
# - role: output replication_role_arn of definitions/prod/global, applied before both regions;
# - bucket and key: outputs bucket_arn and kms_key_arn of definitions/prod/us-east-1.
# On day one this stays null: us-west-2 is applied first as the destination of us-east-1.
replication = {
  role_arn                = "arn:aws:iam::352243449836:role/log-archive-replication"
  destination_bucket_arn  = "arn:aws:s3:::killers-technology-log-archive-us-east-1"
  destination_kms_key_arn = "arn:aws:kms:us-east-1:352243449836:key/66865885-1544-415b-9ed4-a93634443b3e"
}
