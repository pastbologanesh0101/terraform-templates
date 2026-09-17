output "config_file_path" {
  description = "Absolute path to the rendered config file."
  value       = local_file.config.filename
}

output "config_content" {
  description = "The rendered config file content."
  value       = local_file.config.content
}

output "config_file_id" {
  description = "The local_file resource's id (hash of the file content)."
  value       = local_file.config.id
}
