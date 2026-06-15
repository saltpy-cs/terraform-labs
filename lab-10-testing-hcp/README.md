# Lab 10 — Testing & HCP Terraform

## Objectives

This lab has two independent parts. You can complete each part separately.

### Part A — Terraform Testing

- Write `.tftest.hcl` test files using `run` and `assert` blocks
- Use `mock_provider` to run unit tests without creating real cloud resources
- Write integration tests that create and verify real resources
- Use `expect_failures` to test variable validation
- Run targeted tests with `terraform test -filter`

### Part B — HCP Terraform

- Create an HCP Terraform workspace and configure the `cloud` backend
- Understand remote plan and apply execution
- Configure workspace variables (including sensitive credentials)
- Understand how Sentinel policy-as-code enforces governance before applies

**Estimated cost (Part A):** Integration tests create and immediately destroy one S3 bucket (~$0.00).
**Estimated cost (Part B):** S3 bucket only (~$0.00). HCP Terraform free tier covers this lab.

---

## Concepts

### Part A — Terraform Testing

#### The `terraform test` Command

Introduced in Terraform 1.6, `terraform test` runs test files (`.tftest.hcl`) found in a `tests/` directory. It is the official testing framework for Terraform modules.

```bash
terraform test
terraform test -verbose
terraform test -filter=tests/s3_bucket_unit.tftest.hcl
```

#### Test File Structure

A test file contains one or more `run` blocks. Each `run` block executes a plan or apply and can contain `assert` blocks to validate results:

```hcl
run "descriptive_test_name" {
  command = apply  # or plan (default is apply)

  variables {
    bucket_name = "my-test-bucket"
    environment = "dev"
  }

  assert {
    condition     = output.versioning_enabled == true
    error_message = "Expected versioning to be enabled but it was not"
  }
}
```

Between `run` blocks, Terraform does **not** destroy resources — state accumulates within the test execution. After all `run` blocks complete, Terraform destroys everything it created during the test.

#### Mock Providers

Mock providers stub out provider API calls. No real resources are created:

```hcl
mock_provider "aws" {}

run "test_without_real_resources" {
  command = apply

  assert {
    condition     = output.bucket_id != ""
    error_message = "bucket_id should not be empty"
  }
}
```

With a mock provider, Terraform generates fake values for computed attributes (like `id`, `arn`). This makes tests fast and free — ideal for testing module logic, variable validation, and output computations.

#### Testing Variable Validation

Use `expect_failures` to assert that a `run` block should fail with a specific validation error:

```hcl
run "invalid_environment_rejected" {
  command = plan

  variables {
    environment = "invalid"  # not in ["dev", "staging", "prod"]
  }

  # This run is expected to fail because of the variable validation rule.
  expect_failures = [var.environment]
}
```

If the plan does NOT fail (i.e., the validation did not trigger), the test itself fails.

#### Unit vs Integration Tests

| | Unit Tests | Integration Tests |
|---|---|---|
| Provider | `mock_provider` (stubbed) | Real provider (real API calls) |
| Resources created | No | Yes |
| Speed | Fast (< 1s) | Slow (seconds to minutes) |
| Cost | Free | Small (real resources) |
| What you test | Logic, validation, outputs | Actual API behaviour, real IDs |
| When to run | Every commit | Pre-merge, nightly |

A healthy test suite has both: unit tests for fast feedback, integration tests for confidence.

### Part B — HCP Terraform

#### What is HCP Terraform?

HCP Terraform (formerly Terraform Cloud) is a SaaS platform that provides:
- **Remote state storage** with encryption and access control
- **Remote plan and apply execution** — runs happen on HCP Terraform's infrastructure, not your laptop
- **Workspace variables** — store secrets encrypted, not in `.tfvars` files
- **Sentinel** — policy-as-code that runs between plan and apply
- **Team access controls** — fine-grained permissions per workspace

#### The `cloud` Block

The modern way to configure HCP Terraform as your backend:

```hcl
terraform {
  cloud {
    organization = "my-org-name"

    workspaces {
      name = "terraform-labs-lab10"
    }
  }
}
```

After adding this block, run `terraform login` then `terraform init`. Terraform migrates any existing local state to HCP Terraform automatically.

#### Workspace Variables

In HCP Terraform, variables are set in the workspace UI or via the API — not in committed `.tfvars` files. Two types:

- **Terraform variables** — equivalent to `var.x` in your config
- **Environment variables** — set in the runner's shell (used for `AWS_ACCESS_KEY_ID` etc.)

Mark variables as **Sensitive** to encrypt them at rest and redact them from logs.

#### Sentinel Policy as Code

Sentinel is HCP Terraform's policy engine. Policies run after a successful plan but before apply — the "soft mandatory" enforcement point.

Example: require all S3 buckets to have at least one tag:

```python
import "tfplan/v2" as tfplan

# Find all S3 bucket resources in the plan
s3_buckets = filter tfplan.resource_changes as _, rc {
    rc.type is "aws_s3_bucket" and
    rc.mode is "managed" and
    (rc.change.actions contains "create" or rc.change.actions contains "update")
}

# Policy: every bucket must have at least one tag
all_buckets_tagged = rule {
    all s3_buckets as _, bucket {
        length(bucket.change.after.tags) > 0
    }
}

main = rule { all_buckets_tagged }
```

If the policy fails, the apply is blocked until the configuration is fixed or an authorised user overrides it.

---

## Setup

### Prerequisites

- Terraform >= 1.6 installed
- AWS CLI configured (for Part A integration tests and Part B remote apply)
- A free HCP Terraform account at app.terraform.io (Part B only)

### Directory Structure

```
lab-10-testing-hcp/
├── terraform/
│   ├── main.tf              # Root module + cloud block (commented out)
│   ├── variables.tf
│   ├── outputs.tf
│   ├── terraform.tfvars.example
│   └── modules/
│       └── s3-bucket/
│           ├── main.tf
│           ├── variables.tf
│           └── outputs.tf
└── tests/
    ├── s3_bucket_unit.tftest.hcl
    └── s3_bucket_integration.tftest.hcl
```

---

## Exercises — Part A: Testing

### Exercise 1 — Run All Tests

```bash
cd lab-10-testing-hcp/terraform
terraform init
terraform test
```

Expected output: both test files run. Unit tests complete immediately (no real resources). Integration tests create and destroy a real S3 bucket.

```
tests/s3_bucket_integration.tftest.hcl... in progress
  run "create_bucket_with_versioning"... pass
  run "verify_bucket_exists"... pass
tests/s3_bucket_integration.tftest.hcl... tearing down
tests/s3_bucket_integration.tftest.hcl... pass

tests/s3_bucket_unit.tftest.hcl... in progress
  run "versioning_enabled"... pass
  run "versioning_disabled"... pass
  run "invalid_environment_rejected"... pass
tests/s3_bucket_unit.tftest.hcl... tearing down
tests/s3_bucket_unit.tftest.hcl... pass

Success! 5 passed, 0 failed.
```

### Exercise 2 — Deliberately Break a Test

Edit `terraform/modules/s3-bucket/main.tf`. Find the `aws_s3_bucket_versioning` resource and change the `status` to always be `"Suspended"` regardless of the `var.enable_versioning` value:

```hcl
# Change this:
status = var.enable_versioning ? "Enabled" : "Suspended"
# To this (broken):
status = "Suspended"
```

Re-run the tests:
```bash
terraform test -filter=tests/s3_bucket_unit.tftest.hcl
```

Expected: the `versioning_enabled` test fails:
```
  run "versioning_enabled"... fail
    Error: Test assertion failed

      on tests/s3_bucket_unit.tftest.hcl line XX:
      assert {
        condition     = output.versioning_enabled == true
        error_message = "Expected versioning to be enabled when enable_versioning=true"
      }
```

Restore the original code before continuing.

### Exercise 3 — Verbose Mode

```bash
terraform test -verbose -filter=tests/s3_bucket_unit.tftest.hcl
```

Observe: verbose mode shows the mock provider's generated values for computed attributes (e.g., the fake `id` and `arn` values assigned to the bucket). This helps you understand what a mock provider returns and how to write assertions against those values.

### Exercise 4 — Run Only Unit Tests

```bash
terraform test -filter=tests/s3_bucket_unit.tftest.hcl
```

Expected: only unit tests run (no AWS API calls, completes in under 1 second).

This is the command you would run in a pre-commit hook or fast CI job. Integration tests run separately, on a slower schedule.

### Exercise 5 — Write a New Assertion

Open `tests/s3_bucket_unit.tftest.hcl`. Add a new `assert` block inside the first `run` block to verify the bucket ARN format:

```hcl
assert {
  condition     = startswith(output.bucket_arn, "arn:aws:s3:::")
  error_message = "bucket_arn should start with 'arn:aws:s3:::'"
}
```

Re-run the unit tests to confirm the new assertion passes.

---

## Exercises — Part B: HCP Terraform

### Exercise 6 — Create an HCP Terraform Account

1. Go to [app.terraform.io](https://app.terraform.io) and create a free account.
2. Create an **organisation** (e.g. `your-name-terraform-labs`).
3. Create a **workspace** named `terraform-labs-lab10`. Choose "CLI-driven workflow".

### Exercise 7 — Authenticate

```bash
terraform login
```

Follow the prompts: a browser opens, you create an API token, paste it back into the terminal.

Expected:
```
Retrieved token for user yourname

Welcome to HCP Terraform!
```

### Exercise 8 — Configure the Cloud Block

Open `terraform/main.tf`. Find the commented-out `cloud` block and uncomment it:

```hcl
terraform {
  cloud {
    organization = "your-org-name"   # replace with your org name

    workspaces {
      name = "terraform-labs-lab10"
    }
  }
  ...
}
```

Initialise:
```bash
terraform init
```

If you had local state from Part A, Terraform offers to migrate it to HCP Terraform. Type `yes`.

Expected:
```
Initializing HCP Terraform...
Terraform Cloud has been successfully initialized!
```

### Exercise 9 — Configure Workspace Variables

In the HCP Terraform UI:
1. Navigate to your workspace → **Variables**
2. Add **Environment variables** (not Terraform variables):
   - `AWS_ACCESS_KEY_ID` = your AWS access key (mark as **Sensitive**)
   - `AWS_SECRET_ACCESS_KEY` = your AWS secret key (mark as **Sensitive**)
   - `AWS_DEFAULT_REGION` = `us-east-1`

These variables are stored encrypted and injected into the remote runner environment. They never appear in your git repository or plan output.

### Exercise 10 — Remote Apply

```bash
terraform apply
```

Observe: Terraform uploads the configuration to HCP Terraform and runs the plan there. You see a URL in the output:

```
Running plan in HCP Terraform. Output will stream here.
Preparing the remote plan...

To view this run in a browser, visit:
https://app.terraform.io/app/your-org/workspaces/terraform-labs-lab10/runs/run-xxxxx
```

Open that URL in your browser to see the full plan output, including any Sentinel policy checks.

### Exercise 11 — Explore Sentinel (Optional)

In the HCP Terraform UI, navigate to your organisation → **Policy Sets** → **New Policy Set**.

Create a Sentinel policy with the following code that requires all S3 buckets to have at least one tag:

```python
import "tfplan/v2" as tfplan

s3_buckets = filter tfplan.resource_changes as _, rc {
    rc.type is "aws_s3_bucket" and
    rc.mode is "managed" and
    (rc.change.actions contains "create" or rc.change.actions contains "update")
}

all_buckets_tagged = rule {
    all s3_buckets as _, bucket {
        length(keys(lookup(bucket.change.after, "tags", {}))) > 0
    }
}

main = rule { all_buckets_tagged }
```

Apply the policy set to your workspace. Run `terraform plan` again — observe the Sentinel check in the run output.

### Exercise 12 — Destroy

```bash
terraform destroy
```

The destroy runs remotely on HCP Terraform. Expected:
```
Destroy complete! Resources: X destroyed.
```

---

## Key Takeaways

**Testing:**
- **`terraform test`** is the official testing framework, introduced in Terraform 1.6. Test files live in `tests/` and use `.tftest.hcl` extension.
- **Mock providers** enable fast, free unit tests. No real resources are created — computed attributes get synthetic values.
- **`expect_failures`** lets you write tests that assert a variable validation rule triggers correctly.
- **Run only unit tests** in fast CI loops (`-filter`). Run integration tests pre-merge or nightly.
- **Tests clean up after themselves** — Terraform destroys everything it created during a test run.

**HCP Terraform:**
- **Remote execution** moves plans and applies off your laptop onto consistent, auditable infrastructure.
- **Workspace variables** are the right place for secrets. Never commit `AWS_ACCESS_KEY_ID` to a `.tfvars` file in git.
- **The `cloud` block** is the modern replacement for the `remote` backend. One block connects your config to an HCP Terraform workspace.
- **Sentinel** enforces governance between plan and apply — it is the policy-as-code layer for the Professional exam. Policies can be advisory (warn) or mandatory (block).
- **State is stored encrypted in HCP Terraform** — no S3 bucket to manage for remote state.

---

## Cleanup

**Part A:**
```bash
# Tests clean up automatically. Verify no S3 buckets remain:
aws s3 ls | grep tf-lab10
```

**Part B:**
```bash
terraform destroy
```

In HCP Terraform UI: optionally delete the workspace and organisation if no longer needed.
