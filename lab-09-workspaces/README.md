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
│   └── default.tfstate    ← default workspace state
├── dev/
│   └── default.tfstate    ← dev workspace state
├── staging/
│   └── default.tfstate    ← staging workspace state
└── prod/
    └── default.tfstate    ← prod workspace state
```

You configure the backend once with a `prefix`; Terraform handles the path routing automatically:

```hcl
backend "gcs" {
  bucket = "my-state-bucket"
  prefix = "lab09"
}
```

Verify the paths after applying multiple workspaces:
```bash
gsutil ls gs://my-state-bucket/lab09/
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

Edit `terraform.tfvars` and set `gcp_project` and `state_bucket` to your values.

### Configure the Backend

Edit the `backend "gcs"` block in `main.tf`. Replace `YOUR_STATE_BUCKET_NAME` with your actual bucket name.

---

## Exercises

### Exercise 1 — Create a GCS State Bucket

```bash
STATE_BUCKET="tf-lab09-state-$(gcloud config get-value project)"
gsutil mb -l us-central1 gs://${STATE_BUCKET}
gsutil versioning set on gs://${STATE_BUCKET}
```

Expected:
```
Creating gs://tf-lab09-state-your-project-id/...
Enabling versioning for gs://tf-lab09-state-your-project-id/...
```

### Exercise 2 — Configure the Backend and Initialise

Edit `terraform/main.tf`. In the `backend "gcs"` block, replace `YOUR_STATE_BUCKET_NAME` with your actual bucket name (e.g. `tf-lab09-state-your-project-id`).

Also update `terraform.tfvars`:
```hcl
gcp_project  = "your-gcp-project-id"
state_bucket = "tf-lab09-state-your-project-id"
```

Initialise:
```bash
terraform init
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
terraform apply -auto-approve
```

Expected output includes:
```
Outputs:

workspace          = "dev"
machine_type_used  = "e2-micro"
instance_name      = "tf-lab09-dev-instance"
environment_summary = {
  "instance"     = "tf-lab09-dev-instance"
  "machine_type" = "e2-micro"
  "workspace"    = "dev"
}
```

Notice `machine_type_used = "e2-micro"` — the `lookup()` matched `dev`.

### Exercise 6 — Inspect the Environment Summary Output

```bash
terraform output environment_summary
```

Observe the map output showing all three values together. The `workspace` key shows the raw workspace name; `machine_type` shows what `lookup()` resolved it to.

### Exercise 7 — Create and Apply Staging Workspace

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

Note: a new GCE instance was created. The dev instance still exists — these are completely independent state files.

### Exercise 8 — Verify GCS State Paths

```bash
STATE_BUCKET="tf-lab09-state-$(gcloud config get-value project)"
gsutil ls gs://${STATE_BUCKET}/lab09/
```

Expected output (note the workspace-named subdirectories):
```
gs://tf-lab09-state-your-project-id/lab09/dev/
gs://tf-lab09-state-your-project-id/lab09/staging/
```

Drill into a workspace directory:
```bash
gsutil ls gs://${STATE_BUCKET}/lab09/dev/
```

Expected:
```
gs://tf-lab09-state-your-project-id/lab09/dev/default.tfstate
```

This is the GCS path pattern: `<prefix>/<workspace>/default.tfstate`. Compare this to the S3 backend which uses `env:/<workspace>/<key>`.

### Exercise 9 — State Isolation Demo

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

Expected: only staging resources — the dev resources are not visible from here.

This demonstrates that `terraform state list` operates only on the current workspace's state file.

### Exercise 10 — Machine Type Variation

Create a `prod` workspace and run a plan:
```bash
terraform workspace new prod
terraform plan
```

Observe in the plan output:
```
+ machine_type = "e2-small"
```

The `lookup()` in `locals` matched `prod` → `e2-small`. The dev and staging instances use `e2-micro`.

**Do not apply in the prod workspace** unless you are comfortable with the e2-small cost. If you do apply, run `terraform destroy` immediately after observing the output.

To observe the machine type selection without incurring cost:
```bash
terraform plan | grep machine_type
```

Expected:
```
+ machine_type = "e2-small"
```

### Exercise 11 — Selective Destroy (Staging Only)

Switch to staging and destroy:
```bash
terraform workspace select staging
terraform destroy -auto-approve
```

Expected: staging resources destroyed.

Verify dev resources are unaffected:
```bash
terraform workspace select dev
terraform state list
```

Expected: dev resources still listed. Only staging was destroyed.

### Exercise 12 — Delete Workspaces and Full Cleanup

Destroy all remaining workspaces:

```bash
# Destroy prod (if you applied it)
terraform workspace select prod
terraform destroy -auto-approve  # only if prod was applied

# Destroy dev
terraform workspace select dev
terraform destroy -auto-approve

# Switch back to default (staging was already destroyed in Exercise 11)
terraform workspace select default
```

Delete the now-empty workspaces (you must not be in the workspace you are deleting):
```bash
terraform workspace select default
terraform workspace delete dev
terraform workspace delete staging
terraform workspace delete prod  # if it was created
```

Expected:
```
Deleted workspace "dev"!
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

# Destroy default workspace resources (if anything was applied there)
terraform workspace select default
terraform destroy -auto-approve

# Optionally delete the state bucket (this is permanent)
# gsutil rm -r gs://tf-lab09-state-$(gcloud config get-value project)
```
