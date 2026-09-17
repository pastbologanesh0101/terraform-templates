# Terraform Templates

A small, genuinely runnable collection of reusable Terraform modules built
entirely on the **local**, **random**, and **null** providers — no cloud
account, credentials, or billing required. It demonstrates good Terraform
module design (composition, `variables.tf`/`outputs.tf`/`versions.tf`
separation, `templatefile()`, provisioners, environment-specific `.tfvars`)
using only things Terraform can genuinely create on your own filesystem.

Real Terraform CLI (`v1.16.3`, installed via
`brew install hashicorp/tap/terraform`) was used to `init`, `validate`,
`plan`, `apply`, and `destroy` this project on the machine that built it —
see [Testing](#testing) for exact results.

## What it builds

Running `terraform apply` in the root module:

1. Renders an application config file (JSON or YAML) from a template.
2. Generates demo "secret" values (a random password + random id) and
   writes them to a file with `0600` permissions.
3. Runs a shell script (via a `null_resource` `local-exec` provisioner)
   that validates both generated files actually exist and look correct.

No servers, buckets, or infrastructure are provisioned — everything lives
under `./generated/` in this directory.

## Module design

```
terraform-templates/
├── main.tf                # root module: wires the two modules + null_resource
├── variables.tf / outputs.tf / versions.tf
├── envs/
│   ├── dev.tfvars          # example "dev" variable set
│   └── prod.tfvars         # example "prod" variable set
├── modules/
│   ├── config-file-generator/   # renders + writes an app config file
│   │   ├── main.tf / variables.tf / outputs.tf / versions.tf
│   │   └── templates/config.json.tpl, config.yaml.tpl
│   └── secrets-placeholder/     # DEMO-ONLY secret generation pattern
│       ├── main.tf / variables.tf / outputs.tf / versions.tf
├── scripts/validate_generated.sh   # local-exec validation script
├── tests/test_terraform.py         # real subprocess-driven test suite
└── .github/workflows/tests.yml     # CI: setup-terraform + pytest
```

### `config-file-generator`

Takes `app_name`, `environment`, a `feature_flags` list, `log_level`, and
`format` (`json` or `yaml`). Uses `templatefile()` against
`templates/config.json.tpl` / `templates/config.yaml.tpl` (which use HCL
string-template `for` loops to render the feature flag list), then writes
the result with a `local_file` resource. This is the same pattern you'd use
to render a real app's config, kubeconfig snippet, or `.env`-style file from
Terraform variables.

Note on `generated_at`: the rendered file includes a `generated_at` label,
but it is a **static string** (default `"terraform-managed"`), not
`timestamp()`. Embedding a live timestamp in resource content would make
every `apply` show a diff and break idempotency — a deliberate design
choice, documented inline in `modules/config-file-generator/main.tf`.

### `secrets-placeholder`  —  DEMO ONLY, READ THIS

This module generates a `random_password` and `random_id` and writes them
to a local JSON file with `0600` permissions via `local_sensitive_file`.

**This is a pattern demo, not a secrets management solution.** It exists
only to show the *shape* of wiring generated credentials through a module
(e.g. as a `sensitive` output consumed elsewhere). In any real system:

- Do **not** write secrets to a plaintext local file.
- Do **not** rely on Terraform state as a secret store (state is often
  not encrypted and gets shared with teammates/CI).
- **Do** use a real secrets manager/vault — HashiCorp Vault, AWS Secrets
  Manager / SSM Parameter Store (SecureString), GCP Secret Manager, or
  Azure Key Vault — and have Terraform *read* secrets from it via a data
  source, rather than generating and persisting them itself.

This disclaimer is repeated in the module's own header comment
(`modules/secrets-placeholder/main.tf`) and its output descriptions.

### Root module

`main.tf` composes both modules, then declares:

```hcl
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
```

`scripts/validate_generated.sh` checks both files exist, are non-empty, that
the JSON config parses, and that the secrets file has `0600` permissions —
failing the apply (non-zero exit) if anything is wrong. Because its
`triggers` are keyed off each module's stable file-content id, it only
re-runs when the underlying content actually changes, which keeps repeated
applies with unchanged inputs a true no-op.

### Environments: `.tfvars` example

Rather than Terraform workspaces (which share one root module's variable
*values* across state files but don't let you vary top-level input shape
cleanly for a demo like this), this project ships explicit `.tfvars` files
per environment — the more common real-world pattern for "dev vs prod
config":

```bash
terraform plan  -var-file=envs/dev.tfvars
terraform apply -var-file=envs/dev.tfvars

terraform plan  -var-file=envs/prod.tfvars -state=prod.tfstate
terraform apply -var-file=envs/prod.tfvars -state=prod.tfstate
```

`envs/dev.tfvars` uses `debug` log level, JSON format, and 3 feature flags.
`envs/prod.tfvars` uses `warn` log level, **YAML** format, and 1 feature
flag — showing the config-file-generator module branching output format
per environment. (If you'd rather use native workspaces instead of
`-state=`, `terraform workspace new prod && terraform workspace new dev`
works too, since nothing here is workspace-incompatible.)

## Running it yourself

```bash
# 1. Install Terraform (this project was built/tested with v1.16.3)
brew tap hashicorp/tap
brew install hashicorp/tap/terraform

# 2. Initialize
terraform init

# 3. See what would happen
terraform validate
terraform plan -var-file=envs/dev.tfvars

# 4. Actually create the local files
terraform apply -var-file=envs/dev.tfvars -auto-approve

# 5. Inspect the results
cat generated/dev/sampleapp.dev.json
cat generated/dev/sampleapp.dev.secrets.json   # demo secrets, 0600 perms

# 6. Clean up
terraform destroy -var-file=envs/dev.tfvars -auto-approve
```

### Example output

`generated/dev/sampleapp.dev.json` after `terraform apply -var-file=envs/dev.tfvars`:

```json
{
  "app_name": "sampleapp",
  "environment": "dev",
  "log_level": "debug",
  "generated_at": "terraform-managed",
  "feature_flags": [
    { "name": "new-dashboard", "enabled": true },
    { "name": "beta-search", "enabled": true },
    { "name": "debug-toolbar", "enabled": true }
  ]
}
```

`terraform apply` output tail:

```
null_resource.validate_generated_files: Provisioning with 'local-exec'...
null_resource.validate_generated_files (local-exec): [validate] checking config file: ./generated/dev/sampleapp.dev.json
null_resource.validate_generated_files (local-exec): [validate] checking secrets file: ./generated/dev/sampleapp.dev.secrets.json
null_resource.validate_generated_files (local-exec): [validate] secrets file permissions: 600
null_resource.validate_generated_files (local-exec): [validate] OK: all generated artifacts look valid.

Apply complete! Resources: 5 added, 0 changed, 0 destroyed.
```

## Testing

**Terraform CLI was available and used for real** (not the HCL-parsing
fallback). `tests/test_terraform.py` is a `pytest`/`unittest` suite that
shells out to the actual `terraform` binary via `subprocess` against an
isolated temp copy of this project (so test runs never touch your real
`terraform.tfstate`). 10 tests, all currently passing locally:

| # | Test | What it proves |
|---|------|-----------------|
| 1 | `test_01_validate_succeeds` | `terraform validate` exits 0 |
| 2 | `test_02_fmt_check` | all `.tf` files are canonically formatted |
| 3 | `test_03_plan_dev_creates_expected_resource_count` | `plan` reports exactly `5 to add, 0 to change, 0 to destroy` |
| 4 | `test_04_apply_creates_local_files_with_correct_content` | `apply` really creates both files, and their JSON content matches the input variables |
| 5 | `test_05_secrets_file_has_restricted_permissions` | the secrets file is `0600` on disk |
| 6 | `test_06_second_apply_is_idempotent` | a second `plan`/`apply` with the same inputs shows **no changes** |
| 7 | `test_07_prod_tfvars_produces_yaml_config` | switching to `envs/prod.tfvars` renders a `.yaml` file instead |
| 8 | `test_08_destroy_removes_generated_files` | `destroy` actually deletes the generated files from disk |
| 9 | `test_09_module_structure_has_required_files` | both modules have `main/variables/outputs/versions.tf` |
| 10 | `test_10_root_module_has_required_structure_files` | root module + both `.tfvars` files exist |

Run it yourself:

```bash
pip install pytest
python3 -m pytest tests/test_terraform.py -v
```

Last local run: **10 passed in ~34s**.

### CI

`.github/workflows/tests.yml` runs on every push/PR to `main`: it installs
Terraform via `hashicorp/setup-terraform`, runs `terraform fmt -check`,
`terraform validate` on the root module and each module standalone, then
runs the same `pytest` suite (real `init`/`plan`/`apply`/`destroy` against
the `local`/`random`/`null` providers, entirely inside the GitHub-hosted
runner's filesystem).

## Why `.terraform.lock.hcl` is committed

This repo commits `.terraform.lock.hcl` (it is **not** in `.gitignore`).
For a project like this — a root module + its own local sub-modules that
people actually `apply` — pinning exact provider versions/hashes makes
`terraform init` reproducible for every contributor and in CI, which is
the standard HashiCorp guidance. (A shared *library* module meant to be
`source`-d into many unrelated root modules would typically leave the
lock file out, since it doesn't control its own `init`.)

`.terraform/`, `*.tfstate*`, and the `generated/` output directory are all
gitignored, since they're regenerated by running the workflow above and
are either machine-specific or pure build output.

## License

MIT — see [LICENSE](LICENSE).
