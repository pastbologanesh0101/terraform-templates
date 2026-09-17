# Root module: composes config-file-generator + secrets-placeholder, then
# runs a local-exec validation script against the artifacts they produce.

module "config" {
  source = "./modules/config-file-generator"

  app_name      = var.app_name
  environment   = var.environment
  feature_flags = var.feature_flags
  log_level     = var.log_level
  format        = var.config_format
  output_dir    = var.output_dir
}

module "secrets" {
  source = "./modules/secrets-placeholder"

  name_prefix     = var.app_name
  environment     = var.environment
  password_length = var.password_length
  output_dir      = var.output_dir
}

# Validates the generated config + secrets files after every apply.
# Re-runs whenever the underlying file content changes (triggers keyed off
# each module's file id), which also keeps it idempotent: unchanged inputs
# -> unchanged file ids -> no diff -> no re-run on the next apply.
resource "null_resource" "validate_generated_files" {
  triggers = {
    config_file_id  = module.config.config_file_id
    secrets_file_id = module.secrets.demo_id
  }

  provisioner "local-exec" {
    command = "${path.module}/scripts/validate_generated.sh '${module.config.config_file_path}' '${module.secrets.secrets_file_path}'"
  }

  depends_on = [module.config, module.secrets]
}
