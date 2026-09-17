output "config_file_path" {
  description = "Path to the generated application config file."
  value       = module.config.config_file_path
}

output "config_content" {
  description = "Rendered content of the generated config file."
  value       = module.config.config_content
}

output "secrets_file_path" {
  description = "Path to the generated DEMO-ONLY secrets file (0600 permissions)."
  value       = module.secrets.secrets_file_path
}

output "demo_password" {
  description = "The generated demo password. DEMO ONLY - see README for why this is not real secret management."
  value       = module.secrets.demo_password
  sensitive   = true
}
