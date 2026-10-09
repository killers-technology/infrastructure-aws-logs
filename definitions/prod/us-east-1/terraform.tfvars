account_id  = "612062119759" # log-archive
region      = "us-east-1"
environment = "prod"
scope       = "regional"

organization_id = "o-r5s2qddqgq"

# Created by infrastructure-aws-security from Security Tooling (CloudTrail delegated administrator),
# but organization trails are owned by the management account, so its ID is in the ARN.
organization_trail_arn = "arn:aws:cloudtrail:us-east-1:301697000338:trail/organization-trail"

# COMPLIANCE: nobody, root included, can delete a log version or shorten its retention for a year.
object_lock_mode           = "COMPLIANCE"
object_lock_retention_days = 365

transition_to_glacier_days         = 90
expiration_days                    = 2557 # 7 years
noncurrent_version_expiration_days = 30

# DR copy into us-west-2, by value:
# - role: output replication_role_arn of definitions/prod/global, applied before both regions;
# - bucket and key: outputs bucket_arn and kms_key_arn of definitions/prod/us-west-2, applied first.
# Set to null until that side exists.
replication = {
  role_arn                = "arn:aws:iam::612062119759:role/log-archive-replication"
  destination_bucket_arn  = "arn:aws:s3:::log-archive-us-west-2"
  destination_kms_key_arn = "arn:aws:kms:us-west-2:612062119759:key/22222222-2222-4222-8222-222222222222"
}
