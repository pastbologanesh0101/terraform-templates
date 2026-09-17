"""
Real, executable tests for the Terraform Templates project.

These tests shell out to the actual `terraform` CLI (installed via
`brew install hashicorp/tap/terraform` in this environment) against the
root module, which composes the config-file-generator and
secrets-placeholder modules using only the local/random/null providers.
No cloud credentials are required.

Run with:
    python3 -m pytest tests/test_terraform.py -v

Each test that mutates state (apply/destroy) uses its own isolated
temporary working directory copy of the project so tests can run
independently and in sequence without clobbering each other's state.
"""

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DEV_TFVARS = "envs/dev.tfvars"
PROD_TFVARS = "envs/prod.tfvars"


def terraform_available() -> bool:
    return shutil.which("terraform") is not None


def run(cmd, cwd, timeout=120):
    """Run a command, returning CompletedProcess. Raises on unexpected error."""
    return subprocess.run(
        cmd,
        cwd=cwd,
        capture_output=True,
        text=True,
        timeout=timeout,
    )


@unittest.skipUnless(terraform_available(), "terraform CLI not installed")
class TestTerraformWorkflow(unittest.TestCase):
    """Exercises the real terraform init/validate/plan/apply/destroy workflow."""

    @classmethod
    def setUpClass(cls):
        # Work in an isolated copy of the repo so we never touch the
        # developer's real ~/terraform-templates state/generated files
        # while running the test suite.
        cls.tmpdir = tempfile.mkdtemp(prefix="tf-templates-test-")
        cls.workdir = os.path.join(cls.tmpdir, "project")
        shutil.copytree(
            REPO_ROOT,
            cls.workdir,
            ignore=shutil.ignore_patterns(
                ".git", ".terraform", "terraform.tfstate*", "generated", ".terraform.lock.hcl"
            ),
        )
        # Copy the lock file too if it exists, so provider versions match.
        lock_src = REPO_ROOT / ".terraform.lock.hcl"
        if lock_src.exists():
            shutil.copy(lock_src, os.path.join(cls.workdir, ".terraform.lock.hcl"))

        result = run(["terraform", "init", "-input=false", "-no-color"], cwd=cls.workdir, timeout=180)
        assert result.returncode == 0, f"terraform init failed:\n{result.stdout}\n{result.stderr}"

    @classmethod
    def tearDownClass(cls):
        # Best-effort destroy + cleanup of the temp working directory.
        try:
            run(
                ["terraform", "destroy", "-var-file=" + DEV_TFVARS, "-auto-approve", "-input=false", "-no-color"],
                cwd=cls.workdir,
                timeout=60,
            )
        except Exception:
            pass
        shutil.rmtree(cls.tmpdir, ignore_errors=True)

    def test_01_validate_succeeds(self):
        result = run(["terraform", "validate", "-no-color"], cwd=self.workdir)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Success", result.stdout)

    def test_02_fmt_check(self):
        """Ensures all .tf files are canonically formatted (fmt -check -recursive)."""
        result = run(["terraform", "fmt", "-check", "-recursive", "-diff"], cwd=self.workdir)
        self.assertEqual(result.returncode, 0, f"terraform fmt found unformatted files:\n{result.stdout}")

    def test_03_plan_dev_creates_expected_resource_count(self):
        result = run(
            ["terraform", "plan", "-var-file=" + DEV_TFVARS, "-no-color", "-input=false"],
            cwd=self.workdir,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        # 5 resources: local_file, local_sensitive_file, random_password,
        # random_id, null_resource.
        self.assertIn("Plan: 5 to add, 0 to change, 0 to destroy.", result.stdout)

    def test_04_apply_creates_local_files_with_correct_content(self):
        result = run(
            ["terraform", "apply", "-var-file=" + DEV_TFVARS, "-auto-approve", "-input=false", "-no-color"],
            cwd=self.workdir,
            timeout=60,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Apply complete! Resources: 5 added, 0 changed, 0 destroyed.", result.stdout)

        config_path = Path(self.workdir) / "generated" / "dev" / "sampleapp.dev.json"
        secrets_path = Path(self.workdir) / "generated" / "dev" / "sampleapp.dev.secrets.json"

        self.assertTrue(config_path.exists(), "config file was not created")
        self.assertTrue(secrets_path.exists(), "secrets file was not created")

        config_data = json.loads(config_path.read_text())
        self.assertEqual(config_data["app_name"], "sampleapp")
        self.assertEqual(config_data["environment"], "dev")
        self.assertEqual(config_data["log_level"], "debug")
        flag_names = {f["name"] for f in config_data["feature_flags"]}
        self.assertEqual(flag_names, {"new-dashboard", "beta-search", "debug-toolbar"})

        secrets_data = json.loads(secrets_path.read_text())
        self.assertEqual(secrets_data["name_prefix"], "sampleapp")
        self.assertTrue(len(secrets_data["demo_password"]) >= 16)
        self.assertIn("DEMO ONLY", secrets_data["disclaimer"])

    def test_05_secrets_file_has_restricted_permissions(self):
        secrets_path = Path(self.workdir) / "generated" / "dev" / "sampleapp.dev.secrets.json"
        self.assertTrue(secrets_path.exists())
        mode = oct(secrets_path.stat().st_mode)[-3:]
        self.assertEqual(mode, "600", f"expected 0600 permissions, got {mode}")

    def test_06_second_apply_is_idempotent(self):
        """Running apply again with unchanged inputs should show 0 changes."""
        plan_result = run(
            ["terraform", "plan", "-var-file=" + DEV_TFVARS, "-no-color", "-input=false", "-detailed-exitcode"],
            cwd=self.workdir,
        )
        # -detailed-exitcode: 0 = no changes, 1 = error, 2 = changes present.
        self.assertEqual(
            plan_result.returncode,
            0,
            f"expected no-op plan (exit 0), got exit {plan_result.returncode}:\n{plan_result.stdout}",
        )
        self.assertIn("No changes.", plan_result.stdout)

        apply_result = run(
            ["terraform", "apply", "-var-file=" + DEV_TFVARS, "-auto-approve", "-input=false", "-no-color"],
            cwd=self.workdir,
            timeout=60,
        )
        self.assertEqual(apply_result.returncode, 0, apply_result.stdout + apply_result.stderr)
        self.assertIn("Apply complete! Resources: 0 added, 0 changed, 0 destroyed.", apply_result.stdout)

    def test_07_prod_tfvars_produces_yaml_config(self):
        result = run(
            [
                "terraform", "plan", "-var-file=" + PROD_TFVARS, "-no-color", "-input=false",
                "-state=prod.tfstate",
            ],
            cwd=self.workdir,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("sampleapp.prod.yaml", result.stdout)

    def test_08_destroy_removes_generated_files(self):
        destroy_result = run(
            ["terraform", "destroy", "-var-file=" + DEV_TFVARS, "-auto-approve", "-input=false", "-no-color"],
            cwd=self.workdir,
            timeout=60,
        )
        self.assertEqual(destroy_result.returncode, 0, destroy_result.stdout + destroy_result.stderr)
        self.assertIn("Destroy complete! Resources: 5 destroyed.", destroy_result.stdout)

        config_path = Path(self.workdir) / "generated" / "dev" / "sampleapp.dev.json"
        secrets_path = Path(self.workdir) / "generated" / "dev" / "sampleapp.dev.secrets.json"
        self.assertFalse(config_path.exists())
        self.assertFalse(secrets_path.exists())

    def test_09_module_structure_has_required_files(self):
        for module_dir in ["modules/config-file-generator", "modules/secrets-placeholder"]:
            base = Path(self.workdir) / module_dir
            for required in ["main.tf", "variables.tf", "outputs.tf", "versions.tf"]:
                self.assertTrue((base / required).exists(), f"{module_dir} missing {required}")

    def test_10_root_module_has_required_structure_files(self):
        for required in ["main.tf", "variables.tf", "outputs.tf", "versions.tf"]:
            self.assertTrue((Path(self.workdir) / required).exists(), f"root module missing {required}")
        for tfvars in [DEV_TFVARS, PROD_TFVARS]:
            self.assertTrue((Path(self.workdir) / tfvars).exists(), f"missing {tfvars}")


if __name__ == "__main__":
    unittest.main()
