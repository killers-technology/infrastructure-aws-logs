# infrastructure-aws-logs

> Every account ships its logs here, and almost nobody can log in. If an account is compromised, the evidence of what happened is somewhere the attacker can't reach.

The **Log Archive** account (`352243449836`, Security OU). Single environment (`prod`); the Security OU is the one place that isn't split by environment.

| Definition | `scope` | State |
|---|---|---|
| `definitions/prod/global` | `global` (applied from us-east-1) | `tfstate-logs-prod-us-east-1` / `global/terraform.tfstate` |
| `definitions/prod/us-east-1` | `regional` | `tfstate-logs-prod-us-east-1` / `terraform.tfstate` |
| `definitions/prod/us-west-2` | `regional` | `tfstate-logs-prod-us-west-2` / `terraform.tfstate` |

All three deploy to the log-archive account. Resources are gated with `local.global` / `local.regional`: the global definition creates only IAM, the regional ones only what lives in their region.

## What it owns

**Global** (`global.tf`, IAM):

- `log-archive-replication`: the role S3 assumes to replicate each archive bucket into the other (see [the replication role](#the-replication-role)).

**Every region** (`prod/us-east-1`, `prod/us-west-2`):

- **KMS key** `alias/killers-technology-log-archive-<region>`, with rotation on. Its policy allows:
  - IAM administration in this account;
  - **CloudTrail** to encrypt (`kms:GenerateDataKey*`), but only for the organization trail (`aws:SourceArn` and the `aws:cloudtrail:arn` encryption context are both pinned to the trail ARN);
  - **AWS Config** to encrypt, only on behalf of this organization (`aws:SourceOrgID`);
  - principals of the organization to decrypt (`aws:PrincipalOrgID`). That still isn't read access: a reader also needs `s3:GetObject` from this account, and the bucket policy grants it to no one.
- **Bucket** `killers-technology-log-archive-<region>`:
  - versioning, plus **Object Lock** with a default retention (`object_lock_mode`, `object_lock_retention_days`);
  - SSE-KMS with the key above and an S3 Bucket Key;
  - public access fully blocked, `BucketOwnerEnforced` (ACLs off), TLS-only;
  - a lifecycle rule: Glacier after `transition_to_glacier_days`, expiry after `expiration_days`, and noncurrent versions removed `noncurrent_version_expiration_days` later (Object Lock still protects them until their retention date);
  - a bucket policy for:
    - the **CloudTrail organization trail**: `AWSLogs/o-r5s2qddqgq/*`, plus the trail owner's own path `AWSLogs/301697000338/*`, all pinned with `aws:SourceArn`;
    - **AWS Config** delivery channels: `AWSLogs/*/Config/*`, pinned with `aws:SourceOrgID`.
- **Replication** of this bucket into the other region's bucket (optional, see below).

> **Object Lock in `COMPLIANCE` mode cannot be undone.** No one, not even the root user, can delete a locked object version or shorten its retention. While any version is locked, the bucket cannot be deleted either. Try `GOVERNANCE` first if you are experimenting.

## What it reads (plain values in `terraform.tfvars`)

| Variable | Value | Comes from |
|---|---|---|
| `organization_id` | `o-r5s2qddqgq` | the organization (docs/conventions.md) |
| `organization_trail_arn` | `arn:aws:cloudtrail:us-east-1:301697000338:trail/organization-trail` | infrastructure-aws-security creates the trail (see below) |
| `replication.destination_bucket_arn` | `arn:aws:s3:::log-archive-<other region>` | output `bucket_arn` of this project's other definition |
| `replication.destination_kms_key_arn` | `arn:aws:kms:<other region>:352243449836:key/...` | output `kms_key_arn` of this project's other definition |
| `replication.role_arn` | `arn:aws:iam::352243449836:role/log-archive-replication` | output `replication_role_arn` of this project's `prod/global` definition |

**Why the trail ARN has the management account ID.** infrastructure-aws-security creates the trail from Security Tooling, the CloudTrail delegated administrator. AWS still makes the management account the owner of every organization trail. So the trail's ARN, `aws:SourceArn` and the `aws:cloudtrail:arn` encryption context all carry `301697000338`, not `352243449836`. If you pin the policies to the Security Tooling ARN, CloudTrail refuses to create the trail.

## What it publishes (outputs)

| Output | Definition | Consumed by |
|---|---|---|
| `bucket_name` | each region | infrastructure-aws-security, home region (`log_archive_bucket_name`); the Config delivery channels set up by each account's baseline |
| `bucket_arn` | each region | the other region of this project (`replication.destination_bucket_arn`) |
| `kms_key_arn` | each region | infrastructure-aws-security, home region (`log_archive_kms_key_arn`); the other region of this project (`replication.destination_kms_key_arn`) |
| `replication_role_arn` | global | both regions of this project (`replication.role_arn`) |

All of them are copied **by value** into the consumer's `terraform.tfvars`. Nobody reads this state. Outputs that a definition doesn't create are `null` in its state.

## DR replication and apply order

Each bucket is the replica destination of the other one. Replication follows the one-region rule: each definition configures only its own side, the source. The other side reaches it as plain values, not as a live lookup. So the definitions are applied **separately and in order: global first, then the destination, then the source**:

1. Apply `prod/global`. The replication role now exists; its ARN is the output `replication_role_arn`.
2. Apply `prod/us-west-2` with `replication = null`. Its bucket and key now exist.
3. Copy the role ARN and the us-west-2 outputs `bucket_arn` and `kms_key_arn` into `replication` in `prod/us-east-1/terraform.tfvars`, then apply `prod/us-east-1`. us-east-1 now replicates into us-west-2.
4. Copy the role ARN and the us-east-1 outputs into `replication` in `prod/us-west-2/terraform.tfvars`, then apply `prod/us-west-2` again. us-west-2 now replicates into us-east-1.

The committed `terraform.tfvars` show the end state (step 4). The pipeline always runs global definitions before regional ones, so step 1 needs nothing special. On day one, use the pipeline's manual run with the `region` input to apply one region at a time (`global` runs only step 1). Merges to `main` apply `prod/global`, then both regions in parallel.

What gets replicated, and how:

- Replicas are encrypted with the destination region's key.
- Replicas keep their Object Lock retention.
- Replicas of replicas are not sent back, so the two directions don't loop.
- Delete markers are not replicated: deleting in one region never hides the copy in the other.

### The replication role

IAM is global, so the role is created by the global definition (`global.tf`), once, from us-east-1. One role serves both directions:

- **Trust:** `s3.amazonaws.com`, only on behalf of this account (`aws:SourceAccount`).
- **Permissions** (inline policy `replicate-log-archive`), on `killers-technology-log-archive-us-east-1` and `killers-technology-log-archive-us-west-2`:
  - source: `s3:GetReplicationConfiguration` and `s3:ListBucket` on the buckets; `s3:GetObjectVersionForReplication`, `s3:GetObjectVersionAcl`, `s3:GetObjectVersionTagging`, `s3:GetObjectRetention` and `s3:GetObjectLegalHold` on their objects;
  - destination: `s3:ReplicateObject`, `s3:ReplicateDelete` and `s3:ReplicateTags` on their objects;
  - keys: `kms:Decrypt`, `kms:Encrypt` and `kms:GenerateDataKey` on this account's keys of each region, only through S3 in that region (`kms:ViaService`) and only for that region's archive bucket (`kms:EncryptionContext:aws:s3:arn`).

The bucket names come from the naming convention (`killers-technology-log-archive-<region>`, in `main.tf`), and the key statements are pinned by those conditions instead of by key ID, so the global definition never reads the regional states. The key policies already delegate to IAM in this account (the `AccountAdministration` statement): the role's own policy is enough to use both keys.

The apply role `github-logs-apply` may manage roles named `log-archive-*` only, including `iam:PassRole`, which S3 requires when the replication configuration names the role (granted by infrastructure-aws-management, which creates every pipeline role).

## Who writes here

- The **organization trail**. It is multi-region and delivers to `killers-technology-log-archive-us-east-1`. The us-west-2 bucket accepts the same trail, so it can be repointed there if us-east-1 is lost.
- **AWS Config** delivery channels of every account, region by region, through the `config.amazonaws.com` service principal. The channels belong to each account's baseline, not to this project.
- **S3 replication**, from the other region.

Nothing else writes here. Human access is the exception, not the rule.
