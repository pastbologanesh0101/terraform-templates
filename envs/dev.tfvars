# Example variable set for the "dev" environment.
# Usage: terraform plan -var-file=envs/dev.tfvars
#        terraform apply -var-file=envs/dev.tfvars

app_name    = "sampleapp"
environment = "dev"

feature_flags = [
  "new-dashboard",
  "beta-search",
  "debug-toolbar",
]

log_level       = "debug"
config_format   = "json"
password_length = 16
output_dir      = "./generated/dev"
