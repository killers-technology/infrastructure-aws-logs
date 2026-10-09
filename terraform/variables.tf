variable "region" {
  description = "The one region this run deploys to. Global definitions run from us-east-1."
  type        = string

  validation {
    condition     = contains(["us-east-1", "us-west-2"], var.region)
    error_message = "Only us-east-1 (primary) and us-west-2 (DR) are allowed."
  }
}

variable "account_id" {
  description = "Log Archive account ID. The provider refuses to run against any other account."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "account_id must be a 12-digit AWS account ID."
  }
}

variable "environment" {
  description = "Platform environment. The Security OU is not split by environment, so this is always prod."
  type        = string

  validation {
    condition     = var.environment == "prod"
    error_message = "infrastructure-aws-logs only has a prod environment."
  }
}

variable "scope" {
  description = "global: the replication role only (prod/global, applied from us-east-1). regional: the archive bucket and key of one region."
  type        = string
  default     = "regional"

  validation {
    condition     = contains(["global", "regional"], var.scope)
    error_message = "scope must be global or regional."
  }

  validation {
    condition     = var.scope == "regional" || var.region == "us-east-1"
    error_message = "Global definitions are applied from us-east-1."
  }
}

# Regional definitions only ------------------------------------------------------------------------
# Optional so the global definition can leave them out; a regional definition must set every one.

variable "organization_id" {
  description = "AWS Organizations ID. Only services acting for this organization may write here, and only its principals may decrypt."
  type        = string
  default     = null

  validation {
    condition     = var.organization_id == null ? var.scope == "global" : can(regex("^o-[a-z0-9]{10,32}$", var.organization_id))
    error_message = "Regional definitions need organization_id, which must look like o-xxxxxxxxxx."
  }
}

variable "organization_trail_arn" {
  description = "ARN of the organization CloudTrail trail created by infrastructure-aws-security. Organization trails are owned by the management account, so the ARN carries the management account ID."
  type        = string
  default     = null

  validation {
    condition     = var.organization_trail_arn == null ? var.scope == "global" : can(regex("^arn:aws:cloudtrail:(us-east-1|us-west-2):[0-9]{12}:trail/[A-Za-z0-9._-]+$", var.organization_trail_arn))
    error_message = "Regional definitions need organization_trail_arn, a CloudTrail trail ARN in an allowed region."
  }
}

variable "object_lock_mode" {
  description = "Default Object Lock mode. COMPLIANCE: no one, root included, can delete or shorten the retention of a locked object version. GOVERNANCE: principals with s3:BypassGovernanceRetention can."
  type        = string
  default     = null

  validation {
    condition     = var.object_lock_mode == null ? var.scope == "global" : contains(["COMPLIANCE", "GOVERNANCE"], var.object_lock_mode)
    error_message = "Regional definitions need object_lock_mode, COMPLIANCE or GOVERNANCE."
  }
}

variable "object_lock_retention_days" {
  description = "Default retention applied to every new object version."
  type        = number
  default     = null

  validation {
    condition     = var.object_lock_retention_days == null ? var.scope == "global" : var.object_lock_retention_days >= 1
    error_message = "Regional definitions need object_lock_retention_days, at least 1."
  }
}

variable "transition_to_glacier_days" {
  description = "Age in days at which log objects move to S3 Glacier Flexible Retrieval."
  type        = number
  default     = null

  validation {
    condition     = var.transition_to_glacier_days == null ? var.scope == "global" : var.transition_to_glacier_days >= 1
    error_message = "Regional definitions need transition_to_glacier_days, at least 1."
  }
}

variable "expiration_days" {
  description = "Age in days at which log objects expire. Must outlive both the Object Lock retention and the Glacier transition."
  type        = number
  default     = null

  validation {
    condition     = var.expiration_days != null || var.scope == "global"
    error_message = "Regional definitions need expiration_days."
  }

  # Compared once all three are set; a missing one fails its own validation.
  validation {
    condition = (
      var.expiration_days == null || var.object_lock_retention_days == null || var.transition_to_glacier_days == null ? true :
      var.expiration_days > var.object_lock_retention_days && var.expiration_days > var.transition_to_glacier_days
    )
    error_message = "expiration_days must be greater than object_lock_retention_days and transition_to_glacier_days."
  }
}

variable "noncurrent_version_expiration_days" {
  description = "Days a noncurrent (overwritten or expired) version is kept before it is permanently removed. Object Lock still protects it until its retention date."
  type        = number
  default     = 30
}

variable "replication" {
  description = <<-EOT
    DR copy of this bucket into the other region, or null while that side does not exist yet.
    Every value is copied by value: the bucket and key from the other region's definition (its
    outputs), the role from this project's global definition (output replication_role_arn).
    Nothing is looked up live.
  EOT
  type = object({
    role_arn                = string
    destination_bucket_arn  = string
    destination_kms_key_arn = string
  })
  default = null

  validation {
    condition = var.replication == null ? true : (
      can(regex("^arn:aws:iam::[0-9]{12}:role/.+$", var.replication.role_arn)) &&
      can(regex("^arn:aws:s3:::[a-z0-9.-]+$", var.replication.destination_bucket_arn)) &&
      can(regex("^arn:aws:kms:(us-east-1|us-west-2):[0-9]{12}:key/.+$", var.replication.destination_kms_key_arn)) &&
      !strcontains(var.replication.destination_kms_key_arn, ":${var.region}:")
    )
    error_message = "replication needs a role ARN, the destination bucket ARN and the destination key ARN, and the destination must be the other region."
  }
}
