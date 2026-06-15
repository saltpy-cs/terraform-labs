# Lab 09 — Workspaces & Environments

## Objectives

By the end of this lab you will be able to:

- Create, list, select, and delete Terraform workspaces
- Use `terraform.workspace` to branch configuration per environment
- Configure per-workspace resource sizing and naming using `lookup()`
- Understand how workspaces isolate state within a single backend
- Know when workspaces are the right tool and when to use separate root modules
- Configure an S3 backend with automatic workspace state path separation

**Estimated cost:** One EC2 t3.nano per active workspace (~$0.0052/hr each). Running dev + staging simultaneously costs ~$0.01/hr. Destroy all workspaces promptly.

---

## Concepts

### What Are Workspaces?

A Terraform workspace is a **named state snapshot** within a single backend. Every Terraform configuration has at least one workspace: `default`. Additional workspaces can be created, and each maintains completely independent state.

The key insight: **the code is shared, the state is isolated.** You deploy the same configuration multiple times, each to a separate state file, allowing you to have dev/staging/prod environments from a single set of `.tf` files.

```
backend bucket
├── terraform.tfstate          ← default workspace state
└── env:/
    ├── dev/
    │   └── terraform.tfstate  ← dev workspace state
    ├── staging/
    │   └── terraform.tfstate  ← staging workspace state
    └── prod/
        └── terraform.tfstate  ← prod workspace state
```

### The `terraform.workspace` Built-in

`terraform.workspace` is a built-in string value that always contains the name of the currently selected workspace. Use it anywhere you would use a string:

```hcl
locals {
  env = terraform.workspace == "default" ? "dev" : terraform.workspace
}

resource "aws_instance" "web" {
  tags = {
    Name        = "${var.project_name}-${local.env}"
    Environment = local.env
  }
}
```

A common pattern is to treat the `default` workspace as equivalent to `dev`, since you cannot delete or rename `default`.

### Per-Workspace Configuration with `lookup()`

`lookup(map, key, default)` is the standard way to vary resource attributes by workspace:

```hcl
locals {
  instance_types = {
    dev     = "t3.nano"
    staging = "t3.nano"
    prod    = "t3.small"
  }
  instance_type = lookup(local.instance_types, terraform.workspace, "t3.nano")
}
```

When the workspace is `prod`, `instance_type = "t3.small"`. For any other workspace (including `default`), it falls back to `"t3.nano"`.

### Workspace Commands

```bash
# Show current workspace
terraform workspace show

# List all workspaces (* marks the current one)
terraform workspace list

# Create a new workspace and switch to it
terraform workspace new dev

# Switch to an existing workspace
terraform workspace select staging

# Delete a workspace (must not be the current workspace; state must be empty or use -force)
terraform workspace delete staging

# Delete even if state is non-empty (use with caution!)
terraform workspace delete -force staging
```

### S3 Backend with Workspace State Paths

When using the S3 backend, Terraform automatically manages workspace state paths:

- `default` workspace: `s3://bucket/<key>` (the `key` in your backend config)
- Other workspaces: `s3://bucket/env:/<workspace>/<key>`

You configure the backend once; Terraform handles the path routing automatically:

```hcl
terraform {
  backend "s3" {
    bucket = "my-state-bucket"
    key    = "lab09/terraform.tfstate"
    region = "us-east-1"
  }
}
```

Verify the paths after applying multiple workspaces:
```bash
aws s3 ls s3://my-state-bucket/env:/ --recursive
```

### When to Use Workspaces

**Good fits for workspaces:**
- Short-lived feature environments (branch deployments)
- Dev/staging/prod when the infrastructure is identical in structure and the team is small
- Quickly spinning up a copy of the infrastructure for testing
- Keeping environments in sync with the same code

**Poor fits for workspaces:**
- Different teams with different IAM permissions per environment
- Large infrastructure that diverges significantly between environments
- Compliance requirements for strict account-level isolation
- When you need different backend configurations per environment

For production systems with isolation requirements, use **separate root modules** with separate state files and separate AWS accounts. Each environment is a completely independent Terraform configuration that happens to share modules.

### Workspace Limitations

1. **Shared backend, shared permissions** — all workspaces use the same S3 bucket and DynamoDB table. You cannot grant prod-only IAM permissions to the prod workspace.
2. **Same code** — significant divergence between environments requires branching the codebase, which defeats the purpose.
3. **`default` workspace cannot be deleted** — treat it as your baseline.
4. **No workspace-specific provider configuration** — all workspaces use the same provider credentials.

---

## Setup

### Prerequisites

- Terraform >= 1.6 installed
- AWS CLI configured with permissions to create EC2, VPC, and S3 resources
- An S3 bucket for Terraform state (see Exercise 1)

### Create a State Bucket

Either reuse the state bucket from Lab 03, or create a new one:

```bash
aws s3 mb s3://tf-lab09-state-$(whoami) --region us-east-1
aws s3api put-bucket-versioning \
  --bucket tf-lab09-state-$(whoami) \
  --versioning-configuration Status=Enabled
```

### Configure Variables

```bash
cd lab-09-workspaces/terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and set `state_bucket` to your bucket name.

### Configure the Backend

Edit the `backend "s3"` block in `main.tf`. Replace `YOUR_STATE_BUCKET_NAME` with your actual bucket name.

---

## Exercises

### Exercise 1 — Create a State Bucket

```bash
STATE_BUCKET="tf-lab09-state-$(whoami)"
aws s3 mb s3://${STATE_BUCKET} --region us-east-1
aws s3api put-bucket-versioning \
  --bucket ${STATE_BUCKET} \
  --versioning-configuration Status=Enabled
```

Expected:
```
make_bucket: tf-lab09-state-yourname
```

### Exercise 2 — Configure the Backend

Edit `terraform/main.tf`. In the `backend "s3"` block, replace `YOUR_STATE_BUCKET_NAME` with your actual bucket name (e.g. `tf-lab09-state-yourname`).

Also set `state_bucket` in `terraform.tfvars`:
```hcl
state_bucket = "tf-lab09-state-yourname"
```

Initialise:
```bash
terraform init
```

Expected:
```
Initializing the backend...
Successfully configured the backend "s3"!
Terraform has been successfully initialized!
```

### Exercise 3 — Inspect the Default Workspace

```bash
terraform workspace show
```

Expected:
```
default
```

```bash
terraform workspace list
```

Expected:
```
* default
```

The `*` marks the currently selected workspace.

### Exercise 4 — Create and Switch to Dev Workspace

```bash
terraform workspace new dev
```

Expected:
```
Created and switched to workspace "dev"!
...
```

```bash
terraform workspace list
```

Expected:
```
  default
* dev
```

The `*` has moved to `dev`.

### Exercise 5 — Apply in Dev Workspace

```bash
terraform apply
```

Type `yes`. Expected output includes:
```
Outputs:

workspace            = "dev"
instance_type_used   = "t3.nano"
environment_summary  = {
  "environment"   = "dev"
  "instance_id"   = "i-0abc..."
  "instance_type" = "t3.nano"
  "workspace"     = "dev"
}
```

Notice `instance_type_used = "t3.nano"` — the `lookup()` matched `dev`.

### Exercise 6 — Create and Apply Staging Workspace

```bash
terraform workspace new staging
terraform apply
```

Type `yes`. Expected:
```
workspace            = "staging"
instance_type_used   = "t3.nano"
```

Note: a new EC2 instance was created. The dev instance still exists — these are completely independent state files.

### Exercise 7 — Verify Separate State Files in S3

```bash
STATE_BUCKET="tf-lab09-state-$(whoami)"
aws s3 ls s3://${STATE_BUCKET}/ --recursive
```

Expected output (note the `env:/` prefix for non-default workspaces):
```
2024-xx-xx xx:xx:xx  ....  env:/dev/lab09/terraform.tfstate
2024-xx-xx xx:xx:xx  ....  env:/staging/lab09/terraform.tfstate
```

The `default` workspace state would be at `lab09/terraform.tfstate` (no `env:/` prefix).

### Exercise 8 — State Isolation Demo

Switch to dev and list resources:
```bash
terraform workspace select dev
terraform state list
```

Expected: only dev resources (VPC, subnet, instance with dev naming).

Switch to staging and list resources:
```bash
terraform workspace select staging
terraform state list
```

Expected: only staging resources — the dev resources are not visible.

This demonstrates that `terraform state list` only shows the current workspace's state.

### Exercise 9 — Instance Type Variation

Switch to a new `prod` workspace and run a plan:
```bash
terraform workspace new prod
terraform plan
```

Observe in the plan output:
```
+ instance_type = "t3.small"
```

The `lookup()` in `locals` matched `prod` → `t3.small`. The dev and staging instances use `t3.nano`.

**Do not apply in the prod workspace** unless you are comfortable with the t3.small cost (~$0.0208/hr). Run `terraform destroy` immediately if you do apply.

If you want to observe the t3.small selection without incurring cost:
```bash
terraform plan | grep instance_type
```

Expected:
```
+ instance_type = "t3.small"
```

### Exercise 10 — Selective Destroy (Staging Only)

Switch to staging and destroy:
```bash
terraform workspace select staging
terraform destroy
```

Type `yes`. Expected: staging resources destroyed.

Verify dev resources are unaffected:
```bash
terraform workspace select dev
terraform state list
```

Expected: dev resources still listed. Only staging was destroyed.

### Exercise 11 — Delete Workspaces and Full Cleanup

**Destroy all remaining workspaces:**

```bash
# Destroy staging (already done in Exercise 10)
# Destroy prod (if you applied it)
terraform workspace select prod
terraform destroy  # if you applied prod

# Destroy dev
terraform workspace select dev
terraform destroy

# Switch back to default and destroy (if anything was applied there)
terraform workspace select default
```

**Delete the empty workspaces:**
```bash
# You cannot delete the current workspace, so switch to default first
terraform workspace select default
terraform workspace delete dev
terraform workspace delete staging
terraform workspace delete prod  # if it was created
```

Expected:
```
Deleted workspace "dev"!
```

Verify:
```bash
terraform workspace list
```

Expected:
```
* default
```

---

## Key Takeaways

- **Workspaces provide state isolation within a single backend.** Same code, different state files — one per workspace.
- **`terraform.workspace`** is a built-in string value containing the current workspace name. Use it in `locals` and resource tags.
- **`lookup()` enables per-workspace configuration** — different instance types, sizes, or counts without duplicating code.
- **S3 workspace state paths** follow the pattern `env:/<workspace>/<key>`. Terraform manages this routing automatically.
- **Workspace isolation is state-level only** — all workspaces share the same backend credentials and provider configuration. For permission isolation, use separate AWS accounts and backends.
- **The `default` workspace cannot be deleted.** Treat it as a baseline or development environment.
- **Use separate root modules** (not workspaces) when environments have significantly different infrastructure, different teams, or compliance isolation requirements.

---

## Cleanup

```bash
# Destroy resources in each workspace, then delete the workspace
for ws in dev staging prod; do
  terraform workspace select $ws 2>/dev/null && terraform destroy -auto-approve 2>/dev/null
  terraform workspace select default
  terraform workspace delete $ws 2>/dev/null
done

# Destroy default workspace resources
terraform workspace select default
terraform destroy

# Optionally delete the state bucket (this is permanent)
# aws s3 rm s3://tf-lab09-state-$(whoami) --recursive
# aws s3 rb s3://tf-lab09-state-$(whoami)
```
