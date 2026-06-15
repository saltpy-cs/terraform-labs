# Lab 03 — State Management

## Objectives

By the end of this lab you will be able to:

- Explain what Terraform state is, where it lives, and why it exists
- Configure a GCS remote backend (the GCP equivalent of AWS S3+DynamoDB)
- Use `terraform state` subcommands: `list`, `show`, `mv`, `rm`
- Use `terraform import` to bring an existing, manually-created resource under Terraform management
- Explain how GCS provides state locking natively — without a separate locking resource

---

## Concepts

### What is Terraform state?

Terraform needs to map the resources declared in your configuration to real objects in the cloud. It stores this mapping in a **state file** — a JSON document that records every resource it manages, including its full attribute values.

Without state, Terraform would have no way to:
- Know whether a resource already exists (so it can update rather than recreate)
- Track resource IDs assigned by the provider (e.g., `projects/my-project/buckets/my-bucket`)
- Calculate a diff between the desired configuration and current reality

The default state file is `terraform.tfstate` in the working directory (local state). A backup copy is kept in `terraform.tfstate.backup`.

### The state file structure

The state file is JSON with this top-level shape:

```json
{
  "version": 4,
  "terraform_version": "1.9.0",
  "serial": 5,
  "lineage": "a3f1d...",
  "outputs": { ... },
  "resources": [
    {
      "mode": "managed",
      "type": "google_storage_bucket",
      "name": "app_data",
      "provider": "provider[\"registry.terraform.io/hashicorp/google\"]",
      "instances": [
        {
          "schema_version": 0,
          "attributes": {
            "name": "tf-lab03-app-dev-a1b2c3d4",
            "location": "US-CENTRAL1",
            ...
          }
        }
      ]
    }
  ]
}
```

Key fields:
- **`serial`** — incremented on every write; used to detect conflicts between concurrent state writes
- **`lineage`** — a UUID assigned when state is first created; two states with different lineages are from different workspaces and should never be merged
- **`resources`** — the array of managed objects, each with every provider-known attribute

### Local state vs remote state

Local state is fine for learning and solo projects, but creates real problems in teams:

| Problem | What goes wrong |
|---|---|
| State lives on one machine | Others cannot run `terraform plan` |
| No locking | Two people apply simultaneously, corrupting state |
| No history | Hard to see what changed and when |
| Sensitive values in plaintext | State contains secrets in clear text on disk |

**Remote state** solves all four: a shared backend stores the file, locking prevents concurrent writes, versioning provides history, and encryption protects secrets at rest.

### State backends: storage + locking

A **backend** defines two things:
1. **Where** state is stored (e.g., a GCS bucket object)
2. **How** locking works (prevents concurrent state writes)

The backend is configured in the `terraform` block:

```hcl
terraform {
  backend "gcs" {
    bucket = "my-tf-state-bucket"
    prefix = "envs/prod"
  }
}
```

The `prefix` is the directory path within the bucket. Terraform stores the state file at `<prefix>/default.tfstate`. A common convention is `<project>/<environment>`.

### The GCS backend: GCP's native state storage

The GCS backend is the standard choice for GCP-based teams. It requires only a single resource — a GCS bucket. Compare this to AWS:

| Concern | AWS | GCP |
|---|---|---|
| State storage | S3 bucket | GCS bucket |
| State locking | DynamoDB table (separate resource) | GCS bucket (built-in) |
| Total resources needed | 2 | 1 |

**Why GCS locking needs no separate resource:**
GCS implements locking using *conditional writes* and *object generation numbers*. Every GCS object has a `generation` (an integer that increments on every write). When Terraform acquires a lock, it writes a lock file using an `If-Generation-Match: 0` precondition (meaning "only write if this object does not exist yet"). If another process already holds the lock (the object exists), GCS rejects the write with a `412 Precondition Failed` error. When the lock is released, the lock file is deleted, and the next caller can acquire it. This is atomic and consistent — no external coordination service is required.

**Authentication:** the GCS backend authenticates using Application Default Credentials (ADC), the same credential chain as the Google provider itself. After running `gcloud auth application-default login`, no additional configuration is needed.

### The bootstrapping problem

Here is the chicken-and-egg problem with remote state:

- You want Terraform to store its state in GCS
- But a GCS bucket is a GCP resource
- You could manage it with Terraform
- But that Terraform config also needs somewhere to store *its* state

**Solution: two-phase bootstrap**

1. **`bootstrap/`** — a minimal Terraform config that creates the GCS bucket. This config uses *local* state (acceptable because it manages only this one infrastructure resource, which rarely changes after creation).
2. **`app/`** — your main config, which uses the bucket from step 1 as its remote backend.

This is a standard pattern in production. Some teams go further and create the bootstrap bucket using the `gcloud` CLI or the GCP Console to avoid state entirely for that one resource.

### The `terraform state` subcommands

These commands operate on the state file directly without making cloud API calls (except `import`).

| Command | When to use it |
|---|---|
| `terraform state list` | List all resource addresses in state |
| `terraform state show <addr>` | Print all attributes of one resource |
| `terraform state mv <src> <dst>` | Rename or move a resource in state (without destroying it) |
| `terraform state rm <addr>` | Remove a resource from state (without destroying it in the cloud) |
| `terraform state pull` | Print the raw state JSON to stdout |
| `terraform state push` | Overwrite remote state with a local file (dangerous) |

**`state mv`** is essential when refactoring. If you rename `google_storage_bucket.old` to `google_storage_bucket.new` in HCL without using `state mv`, Terraform plans to destroy the old bucket and create a new one. With `state mv`, it updates the pointer in state — no cloud API call is made.

**`state rm`** is used when you want Terraform to stop managing a resource without destroying it. After `state rm`, the bucket still exists in GCP but Terraform no longer tracks it.

### `terraform import`

`terraform import` brings a manually-created resource under Terraform management.

**Terraform 1.5+ preferred approach — `import {}` block:**

```hcl
import {
  id = "my-existing-bucket-name"
  to = google_storage_bucket.manual
}

resource "google_storage_bucket" "manual" {
  name     = "my-existing-bucket-name"
  location = "US"
  # ... other attributes
}
```

Run `terraform plan` — Terraform reads the real resource and shows you what config changes are needed to match. Run `terraform apply` to commit the import.

**CLI approach (still works in all versions):**

```bash
terraform import google_storage_bucket.manual my-existing-bucket-name
```

This writes the resource into state immediately. Then run `terraform plan` to reconcile your config with reality.

The import ID format varies by resource type — always check the "Import" section in the Terraform Registry docs for the resource.

---

## Setup

### Prerequisites

- Terraform >= 1.5 installed
- `gcloud` CLI installed and authenticated:

```bash
gcloud auth application-default login
```

- A GCP project with billing enabled and the Storage API active:

```bash
gcloud services enable storage.googleapis.com --project=YOUR_PROJECT_ID
```

### Verify GCP access

```bash
gcloud auth application-default print-access-token > /dev/null && echo "ADC credentials are valid"
gcloud config get-value project
```

Set your default project if needed:

```bash
gcloud config set project YOUR_PROJECT_ID
```

---

## Exercises

### Exercise 1: Bootstrap — create the GCS state bucket

The `bootstrap/` directory creates the GCS bucket that will store your remote state. It uses local state intentionally — see the Concepts section for why.

```bash
cd terraform/bootstrap
terraform init
```

Expected output (abbreviated):
```
Initializing the backend...
Initializing provider plugins...
- Finding hashicorp/google versions matching "~> 6.0"...
- Finding hashicorp/random versions matching "~> 3.0"...
- Installing hashicorp/google v6.x.x...
- Installing hashicorp/random v3.x.x...

Terraform has been successfully initialized!
```

```bash
terraform apply -auto-approve -var="gcp_project=YOUR_PROJECT_ID"
```

Review the plan. You should see:
- `random_id.suffix` — will be created
- `google_storage_bucket.tf_state` — will be created


Expected output (abbreviated):
```
Apply complete! Resources: 2 added, 0 changed, 0 destroyed.

Outputs:

bucket_name = "tf-lab03-tfstate-a1b2c3d4"
bucket_url  = "gs://tf-lab03-tfstate-a1b2c3d4"
```

**Note the bucket name — you will need it in Exercise 3.**

---

### Exercise 2: Inspect the local state file

The bootstrap config uses local state. Examine it:

```bash
jq '.' terraform.tfstate | head -80
```

Expected output (abbreviated):
```json
{
    "version": 4,
    "terraform_version": "1.x.x",
    "serial": 1,
    "lineage": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
    "outputs": {
        "bucket_name": {
            "value": "tf-lab03-tfstate-a1b2c3d4",
            "type": "string"
        }
    },
    "resources": [
        {
            "mode": "managed",
            "type": "google_storage_bucket",
            "name": "tf_state",
            "instances": [
                {
                    "attributes": {
                        "name": "tf-lab03-tfstate-a1b2c3d4",
                        "location": "US",
                        ...
                    }
                }
            ]
        }
    ]
}
```

Notice:
- `serial` is 1 — this is the first write to state
- `lineage` is a UUID assigned at `terraform init` time — it uniquely identifies this state chain
- The `resources` array contains every attribute of every managed resource

Find the GCS bucket resource specifically:

```bash
jq '[.resources[] | select(.type == "google_storage_bucket")]' terraform.tfstate
```

---

### Exercise 3: Configure the GCS backend in `app/`

Open `terraform/app/main.tf`. Find the `backend "gcs"` block. It currently has a placeholder bucket value.

Replace `REPLACE_WITH_BUCKET_NAME` with the bucket name from Exercise 1:

```hcl
backend "gcs" {
  bucket = "tf-lab03-tfstate-a1b2c3d4"   # your actual bucket name
  prefix = "lab03/app"
}
```

Save the file.

You can also get the value programmatically:

```bash
terraform -chdir=../bootstrap output bucket_name
```

---

### Exercise 4: Initialize the app with the remote backend

```bash
cd ../app
terraform init -var="gcp_project=YOUR_PROJECT_ID"
```

Wait — `terraform init` does not accept `-var` flags. Variables are used by providers and resources, not by the backend itself. The GCS backend authenticates via ADC automatically. Just run:

```bash
terraform init
```

Expected output:
```
Initializing the backend...

Successfully configured the backend "gcs"! Terraform will automatically
use this backend unless the backend configuration changes.

Initializing provider plugins...
...

Terraform has been successfully initialized!
```

```bash
terraform plan -var="gcp_project=YOUR_PROJECT_ID"
```

You should see two resources to create: `random_id.suffix` and `google_storage_bucket.app_data`.

```bash
terraform apply -auto-approve -var="gcp_project=YOUR_PROJECT_ID"
```

Expected:
```
Apply complete! Resources: 2 added, 0 changed, 0 destroyed.

Outputs:

app_bucket_name = "tf-lab03-app-dev-xxxx"
app_bucket_url  = "gs://tf-lab03-app-dev-xxxx"
```

---

### Exercise 5: Verify state is stored in GCS

```bash
gsutil ls gs://<your-state-bucket-name>/
```

Expected output:
```
gs://tf-lab03-tfstate-a1b2c3d4/lab03/
```

```bash
gsutil ls gs://<your-state-bucket-name>/lab03/app/
```

Expected output:
```
gs://tf-lab03-tfstate-a1b2c3d4/lab03/app/default.tfstate
```

You can download and read the state file directly:

```bash
gsutil cat gs://<your-state-bucket-name>/lab03/app/default.tfstate | jq '.'
```

Or using the newer `gcloud storage` command:

```bash
gcloud storage ls gs://<your-state-bucket-name>/lab03/app/
gcloud storage cat gs://<your-state-bucket-name>/lab03/app/default.tfstate
```

---

### Exercise 6: How GCS state locking works

Unlike the AWS S3 backend, the GCS backend does not require a separate DynamoDB table. Locking is built into GCS using **conditional writes**.

When Terraform acquires a lock it:
1. Attempts to write a lock file to GCS using an HTTP `If-Generation-Match: 0` header — meaning "only write if this object does not already exist"
2. If the object already exists (another process holds the lock), GCS returns `412 Precondition Failed` and Terraform shows an error:

```
Error: Error acquiring the state lock

  Error message: writing "gs://my-bucket/lock" failed: googleapi: Error 412:
  Precondition Failed, conditionNotMet
  Lock Info:
    ID:        9a3f...
    Path:      gs://tf-lab03-tfstate-a1b2c3d4/lab03/app/
    Operation: OperationTypeApply
    Who:       alice@workstation
    Created:   2024-01-15 10:32:11
```

3. When the operation completes (or fails), Terraform deletes the lock file, releasing the lock

If Terraform crashes mid-apply and leaves a stale lock, you can release it with:

```bash
terraform force-unlock <LOCK_ID>
```

The key difference from AWS: there is no DynamoDB table to inspect, no `aws dynamodb scan` command to check for active locks. The lock is just an object in the same GCS bucket.

---

### Exercise 7: `terraform state list` — see all managed resources

From the `app/` directory:

```bash
terraform state list
```

Expected output:
```
google_storage_bucket.app_data
random_id.suffix
```

This lists every resource address in state. Resource addresses take the form `<type>.<name>` for root-level resources, or `module.<module_name>.<type>.<name>` for resources inside modules.

---

### Exercise 8: `terraform state show` — inspect a resource

```bash
terraform state show google_storage_bucket.app_data
```

Expected output (abbreviated):
```
# google_storage_bucket.app_data:
resource "google_storage_bucket" "app_data" {
    id                          = "tf-lab03-app-dev-xxxx"
    location                    = "US-CENTRAL1"
    name                        = "tf-lab03-app-dev-xxxx"
    project                     = "your-project-id"
    self_link                   = "https://www.googleapis.com/storage/v1/b/tf-lab03-app-dev-xxxx"
    storage_class               = "STANDARD"
    uniform_bucket_level_access = true
    url                         = "gs://tf-lab03-app-dev-xxxx"

    versioning {
        enabled = false
    }
}
```

This is the full attribute map Terraform has recorded for this resource. Note that this reflects what Terraform *last saw* during an apply or refresh — not necessarily what is in GCP right now. The next exercise demonstrates why that matters.

---

### Exercise 9: Observe state drift

State drift occurs when the real infrastructure diverges from what Terraform has recorded.

1. In the GCP Console, navigate to **Cloud Storage > Buckets**, click on the app bucket, go to **Configuration**, and enable **Object versioning**. (Or use the CLI:)

```bash
gsutil versioning set on gs://tf-lab03-app-dev-xxxx
```

2. Run `terraform state show google_storage_bucket.app_data` again — Terraform still shows `versioning.enabled = false`. State has not been refreshed yet.

3. Run `terraform plan`:

```bash
terraform plan -var="gcp_project=YOUR_PROJECT_ID"
```

Expected output:
```
  ~ resource "google_storage_bucket" "app_data" {
      ~ versioning {
          ~ enabled = true -> false
        }
    }

Plan: 0 to add, 1 to change, 0 to destroy.
```

Terraform detected the drift by calling the GCP API and comparing live attributes to the state file. The plan shows it will disable versioning (to match your config).

4. Apply to reconcile:

```bash
terraform apply -auto-approve -var="gcp_project=YOUR_PROJECT_ID"
```

---

### Exercise 10: `terraform state mv` — rename a resource without recreating it

Suppose you want to rename `google_storage_bucket.app_data` to `google_storage_bucket.primary`. Renaming the HCL block without using `state mv` would cause Terraform to plan a destroy of the old bucket and a create of a new one.

**Step 1:** Move the resource address in state:

```bash
terraform state mv google_storage_bucket.app_data google_storage_bucket.primary
```

Expected output:
```
Move "google_storage_bucket.app_data" to "google_storage_bucket.primary"
Successfully moved 1 object(s).
```

**Step 2:** Update `main.tf` — rename the resource block label from `app_data` to `primary`. Update `outputs.tf` to reference `google_storage_bucket.primary`.

**Step 3:** Verify no destroy/recreate:

```bash
terraform plan -var="gcp_project=YOUR_PROJECT_ID"
```

Expected output:
```
No changes. Your infrastructure matches the configuration.
```

**Step 4:** Restore the original name for the remaining exercises:

```bash
terraform state mv google_storage_bucket.primary google_storage_bucket.app_data
```

Revert the name change in `main.tf` and `outputs.tf`.

---

### Exercise 11: `terraform import` — adopt a manually-created resource

This exercise simulates a common real-world scenario: a bucket was created by hand and you need to bring it under Terraform management.

**Step 1:** Create a GCS bucket manually (outside Terraform):

```bash
# Choose a unique suffix — GCS bucket names are globally unique
SUFFIX=$(date +%s | tail -c 5)
MANUAL_BUCKET="tf-lab03-manual-${SUFFIX}"
echo "Manual bucket name: $MANUAL_BUCKET"

gsutil mb gs://$MANUAL_BUCKET
```

Expected output:
```
Creating gs://tf-lab03-manual-12345/...
```

**Step 2:** Add a resource block for this bucket to `terraform/app/main.tf`:

```hcl
resource "google_storage_bucket" "manual" {
  name     = "tf-lab03-manual-12345"   # replace with your actual bucket name
  location = "US"
  force_destroy = true
  uniform_bucket_level_access = true
}
```

**Step 3:** Without importing, run `terraform plan`:

```bash
terraform plan -var="gcp_project=YOUR_PROJECT_ID"
```

Terraform proposes to *create* the bucket — it does not know the bucket already exists. If you applied, it would fail because GCS bucket names are globally unique and the name is already taken.

**Step 4 (CLI import):** Import the bucket:

```bash
terraform import google_storage_bucket.manual tf-lab03-manual-12345
```

Expected output:
```
google_storage_bucket.manual: Importing from ID "tf-lab03-manual-12345"...
google_storage_bucket.manual: Import prepared!
  Prepared google_storage_bucket for import
google_storage_bucket.manual: Refreshing state... [id=tf-lab03-manual-12345]

Import successful!
```

**Alternative: Terraform 1.5+ `import {}` block**

Instead of running the CLI command, you can declare the import in HCL. Remove the `terraform import` command from above (or if you already ran it, do `terraform state rm google_storage_bucket.manual` to undo it), then add this to `main.tf`:

```hcl
import {
  id = "tf-lab03-manual-12345"
  to = google_storage_bucket.manual
}
```

Run `terraform plan` — Terraform reads the real resource and incorporates it. Run `terraform apply` to commit the import. After apply, remove the `import {}` block (it is no longer needed once the import is recorded in state).

The `import {}` block approach is preferred in Terraform 1.5+ because it is declarative, reviewable in PRs, and integrates with the plan/apply workflow.

**Step 5:** Run `terraform plan` to see what config changes are needed to reconcile:

```bash
terraform plan -var="gcp_project=YOUR_PROJECT_ID"
```

Update your resource block until the plan shows no changes.

---

### Exercise 12: Cleanup

Always destroy in the reverse order of creation — `app/` first, then `bootstrap/`.

**Destroy the app resources:**

```bash
cd terraform/app
terraform destroy -auto-approve -var="gcp_project=YOUR_PROJECT_ID"
```

This destroys the app GCS bucket (and the manually-imported bucket if you left it in state).

**Destroy the bootstrap resources:**

The GCS state bucket has `force_destroy = false` to protect state files. Before destroying bootstrap, you need to remove the state files from the bucket (they were deleted when you ran `terraform destroy` in app/):

```bash
cd ../bootstrap
terraform destroy -auto-approve -var="gcp_project=YOUR_PROJECT_ID"
```

This destroys the state GCS bucket.

> **Note:** After destroying the state bucket, the `app/` backend no longer has a home. That is fine — both configs are gone. If you want to rerun the lab, start from Exercise 1.

---

## Key Takeaways

- **Terraform state** is a JSON mapping between your configuration and real GCP resources. Without it, Terraform cannot track what exists or calculate diffs.
- **Remote state on GCS** is the standard pattern for GCP teams. A single GCS bucket provides storage, versioning, and locking — no separate locking resource is needed.
- **GCS state locking** uses conditional writes (generation check) built into the GCS API. This is architecturally simpler than AWS S3+DynamoDB (one resource instead of two).
- **`terraform state mv`** is the safe way to refactor resource names. It updates the state pointer without any cloud API calls that would destroy and recreate the real resource.
- **`terraform import`** brings manually-created resources under management. Prefer the `import {}` block (Terraform 1.5+) over the CLI command — it is declarative and reviewable.
- **The bootstrapping problem** is real: solve it by using local state for the backend infrastructure itself, and remote GCS state for everything else.
