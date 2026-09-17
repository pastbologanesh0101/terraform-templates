output "secrets_file_path" {
  description = "Path to the generated demo secrets file (permissions 0600)."
  value       = local_sensitive_file.demo_secrets.filename
}

output "demo_password" {
  description = "The generated demo password. DEMO ONLY - never treat this pattern as real secret management."
  value       = random_password.demo.result
  sensitive   = true
}

output "demo_id" {
  description = "The generated demo random id (hex)."
  value       = random_id.demo.hex
}
