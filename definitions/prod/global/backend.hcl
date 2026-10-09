bucket       = "tfstate-logs-prod-us-east-1"
key          = "global/terraform.tfstate"
region       = "us-east-1"
use_lockfile = true
# Encryption: the bucket enforces SSE-KMS with its own key by default.
