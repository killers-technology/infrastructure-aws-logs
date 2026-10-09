# DR copy into the other region's archive bucket. Each region's definition creates only its own side:
# this bucket is the source here and the destination in the other definition. The other side's bucket
# and key reach this run as plain values from terraform.tfvars, never through a live lookup, so the
# destination region is applied first and its outputs are then copied in here. The role comes the
# same way from the global definition (global.tf), which the pipeline applies before both regions.
resource "aws_s3_bucket_replication_configuration" "dr" {
  count = local.regional && var.replication != null ? 1 : 0

  bucket = aws_s3_bucket.logs[0].id
  role   = var.replication.role_arn

  rule {
    id     = "dr-copy"
    status = "Enabled"

    filter {}

    # A delete marker here must not hide the DR copy: that copy is evidence too.
    delete_marker_replication {
      status = "Disabled"
    }

    source_selection_criteria {
      sse_kms_encrypted_objects {
        status = "Enabled"
      }
    }

    # Replicas keep their Object Lock retention; the destination bucket has Object Lock enabled as well.
    destination {
      bucket = var.replication.destination_bucket_arn

      encryption_configuration {
        replica_kms_key_id = var.replication.destination_kms_key_arn
      }
    }
  }

  depends_on = [aws_s3_bucket_versioning.logs]
}
