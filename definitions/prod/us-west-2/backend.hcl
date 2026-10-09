bucket       = "tfstate-logs-prod-us-west-2"
key          = "terraform.tfstate"
region       = "us-west-2"
use_lockfile = true
# Encryption: the bucket enforces SSE-KMS with its own key by default.
