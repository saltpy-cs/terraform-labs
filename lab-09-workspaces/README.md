# Lab 09 — Workspaces & Environments

## Objectives

By the end of this lab you will be able to:

- Create, list, select, and delete Terraform workspaces
- Use `terraform.workspace` to branch configuration per environment
- Configure per-workspace resource sizing and naming using `lookup()`
- Understand how workspaces isolate state within a single GCS backend
- Know when workspaces are the right tool and when to use separate root modules
- Verify GCS workspace state paths and understand how they differ from S3

**Estimated cost:** One GCE e2-micro per active workspace. The first e2-micro is free tier eligible; additional ones cost under $0.01/hr. Destroy all workspaces promptly.

---

## Concepts

### What Are Workspaces?

A Terraform workspace is a **named state snapshot** within a single backend. Every Terraform configuration has at least one workspace: `default`. Additional workspaces can be created, and each maintains completely independent state.

The key insight: **the code is shared, the state is isolated.** You deploy the same configuration multiple times, each to a separate state file, allowing you to have dev/staging/prod environments from a single set of `.tf` files.

### GCS Backend Workspace State Paths

The GCS backend stores workspace state under `<prefix>/<workspace>/default.tfstate`. This differs from the S3 backend, which uses `env:/<workspace>/<key>`.

```
gs://your-bucket/lab09/
├── default/
│   └── default.tfstate    ← default workspace (treated as dev)
├── staging/
│   └── default.tfstate    ← staging workspace state
└── prod/
    └── default.tfstate    ← prod workspace state
```

You configure the backend once with a `prefix`; the bucket is passed at `terraform init` time via `-backend-config` so it never has to be hardcoded:

```hcl
backend "gcs" {
  prefix = "lab09"
}
```

```bash
terraform init -backend-config="bucket=tf-lab09-state-$(gcloud config get-value project)"
```

Exercise 5 verifies this layout once workspaces are applied:
```bash
STATE_BUCKET="tf-lab09-state-$(gcloud config get-value project)"
gcloud storage ls gs://${STATE_BUCKET}/lab09/
```

### The `terraform.workspace` Built-in

`terraform.workspace` is a built-in string value that always contains the name of the currently selected workspace. Use it anywhere you would use a string:

```hcl
locals {
  env = terraform.workspace == "default" ? "dev" : terraform.workspace
}

resource "google_compute_instance" "app" {
  labels = {
    environment = local.env
    workspace   = terraform.workspace
  }
}
```

A common pattern is to treat the `default` workspace as equivalent to `dev`, since you cannot delete or rename `default`.

### Per-Workspace Configuration with `lookup()`

`lookup(map, key, default)` is the standard way to vary resource attributes by workspace:

```hcl
locals {
  machine_types = {
    dev     = "e2-micro"
    staging = "e2-micro"
    prod    = "e2-small"
  }
  machine_type = lookup(local.machine_types, local.env, "e2-micro")
}
```

When the workspace maps to `prod`, `machine_type = "e2-small"`. For any other workspace (including `default`), it falls back to `"e2-micro"`.

### Workspace Commands

These are for reference — the exercises walk through each command in context.

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

# Delete even if state is non-empty (use with caution)
terraform workspace delete -force staging
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
- Compliance requirements for strict project-level isolation
- When you need different backend configurations per environment

For production systems with isolation requirements, use **separate root modules** with separate state files and separate GCP projects. Each environment is a completely independent Terraform configuration that happens to share modules.

### Workspace Limitations

1. **Shared backend, shared permissions** — all workspaces use the same GCS bucket. You cannot grant prod-only IAM permissions to the prod workspace.
2. **Same code** — significant divergence between environments requires branching the codebase, which defeats the purpose.
3. **`default` workspace cannot be deleted** — treat it as your baseline.
4. **No workspace-specific provider configuration** — all workspaces use the same GCP project and credentials.

---

## Setup

### Prerequisites

- Terraform >= 1.6 installed
- `gcloud` CLI authenticated (`gcloud auth application-default login`)
- A GCP project with the Compute Engine API enabled
- A GCS bucket for Terraform state (see Exercise 1)

### Configure Variables

```bash
cd lab-09-workspaces/terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and set `gcp_project` to your project ID. No other values need changing.

---

## Exercises

### Exercise 1 — Create a GCS State Bucket

```bash
STATE_BUCKET="tf-lab09-state-$(gcloud config get-value project)"
gcloud storage buckets create gs://${STATE_BUCKET} --location=us-central1
gcloud storage buckets update gs://${STATE_BUCKET} --versioning
```

Expected:
```
Creating gs://tf-lab09-state-your-project-id/...
Enabling versioning for gs://tf-lab09-state-your-project-id/...
```

### Exercise 2 — Configure the Backend and Initialise

The backend uses a partial configuration — the bucket name is passed at init time so it never has to be hardcoded in `main.tf`:

```bash
STATE_BUCKET="tf-lab09-state-$(gcloud config get-value project)"
terraform init -backend-config="bucket=${STATE_BUCKET}"
```

Expected:
```
Initializing the backend...
Successfully configured the backend "gcs"!
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

### Exercise 4 — Apply in Default Workspace

You are on the `default` workspace. The `local.env` in `main.tf` maps `default → "dev"`, so resources are named as if you were in a dev environment — without creating a separate workspace:

```bash
terraform apply -auto-approve
```

Expected output includes:
```
Outputs:

workspace          = "default"
machine_type_used  = "e2-micro"
instance_name      = "tf-lab09-dev-instance"
environment_summary = {
  "instance"     = "tf-lab09-dev-instance"
  "machine_type" = "e2-micro"
  "workspace"    = "default"
}
```

`workspace = "default"` is the raw workspace name, but `instance_name = "tf-lab09-dev-instance"` — the `default → "dev"` mapping in `local.env` has named the resources as dev. This is the recommended pattern: use `default` as your development environment rather than creating a separate `dev` workspace, since `default` can never be deleted.

### Exercise 5 — Inspect the Environment Summary

```bash
terraform output environment_summary
```

Observe that `workspace` shows `"default"` (the raw workspace name) while `instance` shows `"tf-lab09-dev-instance"`. The `local.env` mapping is the bridge: `terraform.workspace == "default" ? "dev" : terraform.workspace`. The `machine_type` key shows what `lookup()` resolved for this workspace.

### Exercise 6 — Create and Apply Staging Workspace

```bash
terraform workspace new staging
terraform apply -auto-approve
```

Expected output includes:
```
workspace          = "staging"
machine_type_used  = "e2-micro"
instance_name      = "tf-lab09-staging-instance"
```

A new GCE instance was created. The default workspace's dev instance still exists — these are completely independent state files.

### Exercise 7 — Verify GCS State Paths

```bash
STATE_BUCKET="tf-lab09-state-$(gcloud config get-value project)"
gcloud storage ls -r gs://${STATE_BUCKET}/lab09/
```

Expected output:
```
gs://tf-lab09-state-your-project-id/lab09/default/default.tfstate
gs://tf-lab09-state-your-project-id/lab09/staging/default.tfstate
```

This is the GCS path pattern: `<prefix>/<workspace>/default.tfstate`. Compare this to the S3 backend which uses `env:/<workspace>/<key>`.

### Exercise 8 — State Isolation Demo

List resources in the default workspace:
```bash
terraform workspace select default
terraform state list
```

Expected: only default workspace resources (VPC, subnet, instance with dev naming).

Switch to staging and list resources:
```bash
terraform workspace select staging
terraform state list
```

Expected: only staging resources — the default workspace's resources are not visible from here.

This demonstrates that `terraform state list` operates only on the current workspace's state file.

### Exercise 9 — Machine Type Variation

Create a `prod` workspace and run a plan:
```bash
terraform workspace new prod
terraform plan
```

Observe in the plan output:
```
+ machine_type = "e2-small"
```

The `lookup()` in `locals` matched `prod` → `e2-small`. The default (dev) and staging instances use `e2-micro`.

**Do not apply in the prod workspace** unless you are comfortable with the e2-small cost. If you do apply, run `terraform destroy` immediately after observing the output.

To observe the machine type selection without incurring cost:
```bash
terraform plan | grep machine_type
```

Expected:
```
+ machine_type = "e2-small"
```

### Exercise 10 — Selective Destroy (Staging Only)

Switch to staging and destroy:
```bash
terraform workspace select staging
terraform destroy -auto-approve
```

Expected: staging resources destroyed.

Verify default workspace resources are unaffected:
```bash
terraform workspace select default
terraform state list
```

Expected: default workspace resources still listed. Only staging was destroyed.

### Exercise 11 — Delete Workspaces and Full Cleanup

Destroy all remaining workspaces:

```bash
# Destroy prod (only if you applied it in Exercise 9)
terraform workspace select prod
terraform destroy -auto-approve

# Switch back to default and destroy dev resources
terraform workspace select default
terraform destroy -auto-approve
```

Delete the now-empty non-default workspaces (you must not be in the workspace you are deleting):
```bash
terraform workspace select default
terraform workspace delete staging
terraform workspace delete prod  # if it was created
```

Expected:
```
Deleted workspace "staging"!
```

Verify only `default` remains:
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
- **`terraform.workspace`** is a built-in string value containing the current workspace name. Use it in `locals`, labels, and resource names.
- **`lookup()` enables per-workspace configuration** — different machine types, sizes, or counts without duplicating code.
- **GCS workspace state paths** follow the pattern `<prefix>/<workspace>/default.tfstate`. This differs from S3's `env:/<workspace>/<key>` pattern. Terraform manages the routing automatically.
- **Workspace isolation is state-level only** — all workspaces share the same GCS bucket and GCP project credentials. For permission isolation, use separate GCP projects and backends.
- **The `default` workspace cannot be deleted.** Treat it as your development environment and map it to `"dev"` via `local.env = terraform.workspace == "default" ? "dev" : terraform.workspace`. This avoids an orphaned `dev` workspace that mirrors `default`.
- **Use separate root modules** (not workspaces) when environments have significantly different infrastructure, different teams, or compliance isolation requirements.

---

## Cleanup

```bash
# Destroy resources in each non-default workspace, then delete the workspace
for ws in staging prod; do
  terraform workspace select $ws 2>/dev/null && terraform destroy -auto-approve 2>/dev/null
  terraform workspace select default
  terraform workspace delete $ws 2>/dev/null
done

# Destroy default workspace resources
terraform workspace select default
terraform destroy -auto-approve

# Optionally delete the state bucket (this is permanent)
# gcloud storage rm --recursive gs://tf-lab09-state-$(gcloud config get-value project)
```
