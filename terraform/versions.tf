terraform {
  required_version = ">= 1.10" # S3 native locking (use_lockfile)

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.68"
    }
  }

  backend "s3" {} # partial configuration, completed by definitions/<env>/<region>/backend.hcl
}
