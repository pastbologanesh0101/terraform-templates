# Example variable set for the "prod" environment.
# Usage: terraform plan -var-file=envs/prod.tfvars
#        terraform apply -var-file=envs/prod.tfvars

app_name    = "sampleapp"
environment = "prod"

feature_flags = [
  "new-dashboard",
]

log_level       = "warn"
config_format   = "yaml"
password_length = 32
output_dir      = "./generated/prod"
