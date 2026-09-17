# config-file-generator
#
# Renders an application config file (JSON or YAML) from a templatefile()
# call and writes it to disk with the local_file resource. This demonstrates
# a common IaC pattern: generating environment-specific config artifacts
# (feature flags, log levels, app metadata) as part of a Terraform apply,
# so the rendered file always matches the declared variables.

locals {
  # NOTE: intentionally NOT using timestamp() here. Embedding a changing
  # timestamp in the rendered content would make every "terraform apply"
  # show a diff, breaking idempotency. generated_at is instead a stable,
  # user-supplied label (defaults to the environment name) so repeated
  # applies with unchanged inputs produce zero-diff plans.
  rendered_content = var.format == "json" ? templatefile(
    "${path.module}/templates/config.json.tpl",
    {
      app_name      = var.app_name
      environment   = var.environment
      log_level     = var.log_level
      feature_flags = var.feature_flags
      generated_at  = var.generated_at_label
    }
    ) : templatefile(
    "${path.module}/templates/config.yaml.tpl",
    {
      app_name      = var.app_name
      environment   = var.environment
      log_level     = var.log_level
      feature_flags = var.feature_flags
      generated_at  = var.generated_at_label
    }
  )

  file_extension = var.format == "json" ? "json" : "yaml"
  file_name      = "${var.app_name}.${var.environment}.${local.file_extension}"
}

resource "local_file" "config" {
  filename        = "${var.output_dir}/${local.file_name}"
  content         = local.rendered_content
  file_permission = "0644"
}
