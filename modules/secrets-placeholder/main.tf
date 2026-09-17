# secrets-placeholder
#
# *** DEMO / PATTERN-ONLY MODULE - DO NOT USE FOR REAL SECRETS ***
#
# This module demonstrates the SHAPE of generating example secret material
# with the `random` provider (random_password / random_id) and persisting
# it to a local file with restricted permissions. It exists purely to show
# how a module *could* wire generated credentials into downstream resources
# (e.g. passed as a sensitive output to another module/resource).
#
# In a real system you would NEVER write secrets to a plaintext local file
# or commit generated values to Terraform state without encryption. Real
# secrets belong in a dedicated secrets manager / vault, such as:
#   - HashiCorp Vault
#   - AWS Secrets Manager / SSM Parameter Store (SecureString)
#   - GCP Secret Manager
#   - Azure Key Vault
# Terraform would typically reference secrets FROM those systems (via data
# sources) rather than generating and storing them itself. See README.md
# for the full disclaimer.

resource "random_password" "demo" {
  length           = var.password_length
  special          = true
  override_special = "!@#%&*-_=+"
}

resource "random_id" "demo" {
  byte_length = 8
}

locals {
  secrets_content = jsonencode({
    name_prefix   = var.name_prefix
    environment   = var.environment
    demo_password = random_password.demo.result
    demo_id       = random_id.demo.hex
    disclaimer    = "DEMO ONLY - not a real secret. Do not use in production. Use a real secrets manager/vault instead."
  })

  file_name = "${var.name_prefix}.${var.environment}.secrets.json"
}

resource "local_sensitive_file" "demo_secrets" {
  filename        = "${var.output_dir}/${local.file_name}"
  content         = local.secrets_content
  file_permission = "0600"
}
