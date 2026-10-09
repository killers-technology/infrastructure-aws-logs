account_id  = "612062119759" # log-archive
region      = "us-west-2"
environment = "prod"
scope       = "regional"

organization_id = "o-r5s2qddqgq"

# The trail is multi-region and delivers to log-archive-us-east-1. This bucket still accepts it,
# so the trail can be repointed here if us-east-1 is lost.
organization_trail_arn = "arn:aws:cloudtrail:us-east-1:301697000338:trail/organization-trail"

object_lock_mode           = "COMPLIANCE"
object_lock_retention_days = 365

transition_to_glacier_days         = 90
expiration_days                    = 2557 # 7 years
noncurrent_version_expiration_days = 30

# DR copy back into us-east-1, by value:
# - role: output replication_role_arn of definitions/prod/global, applied before both regions;
# - bucket and key: outputs bucket_arn and kms_key_arn of definitions/prod/us-east-1.
# On day one this stays null: us-west-2 is applied first as the destination of us-east-1.
replication = {
  role_arn                = "arn:aws:iam::612062119759:role/log-archive-replication"
  destination_bucket_arn  = "arn:aws:s3:::log-archive-us-east-1"
  destination_kms_key_arn = "arn:aws:kms:us-east-1:612062119759:key/11111111-1111-4111-8111-030388906125"
}
