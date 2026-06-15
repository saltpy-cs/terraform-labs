# Lab 07 — IAM and Provider Aliases (GCP)

## Objectives

By the end of this lab you will be able to:

- Create and manage GCP service accounts with Terraform
- Assign IAM roles to service accounts and users at project and resource level
- Explain the difference between `google_project_iam_member` (additive) and `google_project_iam_binding` (authoritative)
- Use provider aliases to manage resources in multiple GCP regions without code duplication
- Configure a second lightweight provider (`http`) to demonstrate multi-provider concepts in a single configuration

**Estimated cost:** GCE e2-micro in us-central1 is covered by the GCP Always Free tier. GCS Standard storage is ~$0.020/GB/month (essentially $0.00 for empty buckets). Total: ~$0.00 for the duration of the lab.

---

## Concepts

### GCP IAM Model

GCP IAM has three components:

- **Principal** (who): `user:alice@example.com`, `serviceAccount:sa@project.iam.gserviceaccount.com`, `group:...`, `allUsers`
- **Role** (what): `roles/storage.objectViewer`, `roles/editor`, `roles/storage.objectAdmin`, custom roles
- **Resource** (where): project, bucket, dataset, Compute instance, etc.

A **binding** connects a principal to a role on a resource. Terraform provides several resources to manage bindings — they differ in how authoritative they are.

### Service Accounts

A **service account** is both:
- A **principal** — it can be granted roles (just like a user)
- An **identity** — applications and GCE instances authenticate *as* a service account to call GCP APIs

```hcl
resource "google_service_account" "app" {
  account_id   = "my-app-sa"
  display_name = "Application Service Account"
}
```

The `email` attribute (`my-app-sa@project.iam.gserviceaccount.com`) is used to reference the SA in IAM bindings.

### IAM Binding Types

There are three Terraform resources for project-level IAM. They differ critically in authoritative scope:

| Resource | Scope | Behaviour |
|---|---|---|
| `google_project_iam_member` | One principal + role pair | **Additive.** Adds the binding without touching others. Safe in shared environments. |
| `google_project_iam_binding` | One role across all members | **Authoritative for the role.** Replaces the entire member list for that role. Any manually-added members with that role are removed on next `apply`. |
| `google_project_iam_policy` | Entire project policy | **Authoritative for the whole policy.** Most dangerous — can lock you out if misconfigured. |

The same three-tier pattern applies to resource-level IAM (e.g., `google_storage_bucket_iam_member`, `google_storage_bucket_iam_binding`, `google_storage_bucket_iam_policy`).

**Rule of thumb:** use `iam_member` unless you explicitly need to own the full member list for a role.

### Resource-level IAM vs Project-level IAM

**Least privilege** means granting access to the smallest scope necessary. Prefer:

```hcl
# Good: grants access to one specific bucket
resource "google_storage_bucket_iam_member" "user_access" {
  bucket = google_storage_bucket.us.name
  role   = "roles/storage.objectViewer"
  member = "user:alice@example.com"
}
```

Over:

```hcl
# Broader: grants access to all buckets in the project
resource "google_project_iam_member" "user_access" {
  project = var.gcp_project
  role    = "roles/storage.objectViewer"
  member  = "user:alice@example.com"
}
```

### Provider Aliases

A provider alias lets you manage resources in multiple regions — or multiple GCP projects — from a single configuration:

```hcl
# Default provider (no alias)
provider "google" {
  project = var.gcp_project
  region  = "us-central1"
}

# Aliased provider for Europe
provider "google" {
  alias   = "europe"
  project = var.gcp_project
  region  = "europe-west1"
}
```

Resources that do not specify `provider` use the default. Resources that specify `provider = google.europe` are managed via the aliased instance:

```hcl
resource "google_storage_bucket" "europe" {
  provider = google.europe
  name     = "my-europe-bucket"
  location = "EU"
}
```

In state, the provider reference for an aliased resource looks like:
`provider["registry.terraform.io/hashicorp/google"].europe`

### Multi-Provider Configurations

Terraform can manage resources from multiple independent providers in one configuration. Each provider is downloaded and authenticated separately during `terraform init`. The `http` provider in this lab needs no credentials — it simply fetches a URL and returns the response body. This makes it a clean example for demonstrating multi-provider without any additional auth setup.

### `google_service_account_key`

The `google_service_account_key` resource generates a JSON key file for a service account. The key is base64-encoded in state. In production, prefer **Workload Identity Federation** (attaches a SA to a GCE instance or CI/CD identity without a long-lived key). The key is included here for educational purposes — you can inspect it and see how Terraform manages secrets.

---

## Setup

### Prerequisites

- Terraform >= 1.5 installed
- `gcloud` CLI installed and initialised (`gcloud init`)
- A GCP project with billing enabled
- Your GCP user account email (the one you log in to GCP with)

### Authenticate with GCP

```bash
gcloud auth application-default login
```

Follow the browser prompt to authorise. Verify:

```bash
gcloud auth application-default print-access-token
```

If a token is printed, Application Default Credentials (ADC) are working. Terraform uses ADC automatically — no environment variables needed.

### Configure Variables

```bash
cd lab-07-gcp-provider/terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
gcp_project     = "your-actual-project-id"
gcp_region      = "us-central1"
gcp_zone        = "us-central1-a"
your_user_email = "you@example.com"
```

Find your project ID: `gcloud config get-value project`

---

## Exercises

### Exercise 1 — Configure Variables and Initialise

Copy and fill in the variables file:

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your project ID and email
```

Initialise Terraform and observe which providers are downloaded:

```bash
terraform init
```

Expected output includes both the `google` and `http` providers being installed:

```
- Installing hashicorp/google v6.x.x...
- Installing hashicorp/http v3.x.x...
- Installing hashicorp/random v3.x.x...
Terraform has been successfully initialized!
```

### Exercise 2 — Plan and Identify Provider Usage

```bash
terraform plan
```

Review the plan output. The `provider` meta-argument is not shown as an attribute in plan output — Terraform uses it internally for routing but does not print it. The way to identify which provider a resource uses is to read the configuration: look for `provider = google.europe` in the resource block in `main.tf`.

In the plan, confirm `google_storage_bucket.europe` appears alongside the other resources. After apply, Exercise 9 shows how to verify the provider assignment via state.

Count how many resources the plan will create — only `google_storage_bucket.europe` uses the aliased `google.europe` provider.

### Exercise 3 — Apply

```bash
terraform apply -auto-approve
```

Expected output:

```
Apply complete! Resources: 9 added, 0 changed, 0 destroyed.

Outputs:

service_account_email = "tf-lab07-sa@your-project.iam.gserviceaccount.com"
us_bucket_url         = "gs://tf-lab07-xxxx-us"
europe_bucket_url     = "gs://tf-lab07-xxxx-eu"
app_instance_name     = "tf-lab07-app"
my_external_ip        = "1.2.3.4"
```

### Exercise 4 — Inspect the Service Account

```bash
gcloud iam service-accounts list
```

Expected: your Terraform-created SA appears in the list.

View its details:

```bash
gcloud iam service-accounts describe tf-lab07-sa@$(terraform output -raw service_account_email | cut -d@ -f2)
```

Or more simply, using the output directly:

```bash
gcloud iam service-accounts describe $(terraform output -raw service_account_email)
```

### Exercise 5 — Verify IAM Bindings

Check the project-level IAM member Terraform created for the service account:

```bash
gcloud projects get-iam-policy $(gcloud config get-value project) \
  --flatten="bindings[].members" \
  --format="table(bindings.role,bindings.members)" \
  | grep tf-lab07
```

Expected: a line showing `roles/storage.objectViewer` bound to the service account.

Check the resource-level IAM on the US bucket:

```bash
gcloud storage buckets get-iam-policy $(terraform output -raw us_bucket_url)
```

Expected: a binding for `user:you@example.com` with `roles/storage.objectViewer`.

### Exercise 6 — Additive vs Authoritative IAM

This exercise demonstrates the difference between `iam_member` and `iam_binding`.

**Step 1: Add an extra bucket-level binding using `iam_member`.**

In `main.tf`, add a second `google_storage_bucket_iam_member` that grants your user `roles/storage.objectAdmin` on the US bucket:

```hcl
resource "google_storage_bucket_iam_member" "user_admin" {
  bucket = google_storage_bucket.us.name
  role   = "roles/storage.objectAdmin"
  member = "user:${var.your_user_email}"
}
```

Apply:

```bash
terraform apply -auto-approve
```

Check the policy again:

```bash
gcloud storage buckets get-iam-policy $(terraform output -raw us_bucket_url)
```

Expected: both `roles/storage.objectViewer` and `roles/storage.objectAdmin` are present for your user. The `iam_member` resource added the new binding without touching the existing one.

**Step 2: Switch to `iam_binding` and observe authoritative behaviour.**

Replace the two `google_storage_bucket_iam_member` resources for your user with a single `google_storage_bucket_iam_binding`:

```hcl
resource "google_storage_bucket_iam_binding" "user_binding" {
  bucket  = google_storage_bucket.us.name
  role    = "roles/storage.objectAdmin"
  members = ["user:${var.your_user_email}"]
}
```

Remove or comment out `google_storage_bucket_iam_member.user_access` and `google_storage_bucket_iam_member.user_admin`.

Plan and observe:

```bash
terraform plan
```

Expected: the plan removes the `iam_member` resources and adds the `iam_binding`. The `iam_binding` will be authoritative — it will replace all members currently holding `roles/storage.objectAdmin` on this bucket.

Apply, then check the policy:

```bash
terraform apply -auto-approve
gcloud storage buckets get-iam-policy $(terraform output -raw us_bucket_url)
```

Expected: only the members listed in the `iam_binding` hold `roles/storage.objectAdmin`.

**Step 3: Restore the original configuration.**

Switch back to `google_storage_bucket_iam_member` resources as originally defined and re-apply.

### Exercise 7 — Inspect the Europe Bucket via State

```bash
terraform state show google_storage_bucket.europe
```

Expected output includes the provider reference:

```
# google_storage_bucket.europe:
resource "google_storage_bucket" "europe" {
    id       = "tf-lab07-xxxx-eu"
    location = "EU"
    name     = "tf-lab07-xxxx-eu"
    ...
}
```

The state file internally records the provider as `provider["registry.terraform.io/hashicorp/google"].europe`.

Compare with the US bucket:

```bash
terraform state show google_storage_bucket.us
```

Note the different `location` value (`US` vs `EU`).

### Exercise 8 — The http Data Source

```bash
terraform output my_external_ip
```

Expected: your public IP address (the IP your machine uses to reach the internet). This value was fetched by the `http` provider when Terraform ran — no GCP credentials were needed.

View how the data source is defined:

```bash
terraform state show data.http.metadata
```

This illustrates that Terraform can call any HTTP endpoint and use its response body as a data source.

### Exercise 9 — Provider Alias in State

Inspect how Terraform records the provider for the aliased resource:

```bash
terraform state list | grep bucket
```

Expected:

```
google_storage_bucket.europe
google_storage_bucket.us
```

Both are managed by the `google` provider, but the alias distinguishes which provider instance manages which resource. You can verify by pulling the raw state entry:

```bash
terraform show -json | jq '.values.root_module.resources[] | select(.address | contains("europe"))'
```

### Exercise 10 — Destroy

```bash
terraform destroy -auto-approve
```

Expected:

```
Destroy complete! Resources: 9 destroyed.
```

Verify cleanup:

```bash
gcloud compute instances list
gcloud storage buckets list
gcloud iam service-accounts list
```

No `tf-lab07` resources should remain.

---

## Key Takeaways

- Use `google_project_iam_member` (or `google_storage_bucket_iam_member`) for **additive** IAM — it adds one binding without touching anything else. This is safe to use alongside manually-managed IAM.
- Use `google_project_iam_binding` when you want **authoritative control over a role** — it replaces all members holding that role. Any members added outside Terraform will be removed on the next `apply`.
- Use `google_project_iam_policy` only when you intend to own the **entire project policy** — it is the most dangerous and can lock you out.
- **Prefer resource-level IAM** (`google_storage_bucket_iam_member`) over project-level IAM when following least privilege.
- **Provider aliases** handle multi-region deployments with no code duplication. Resources reference the alias with `provider = google.europe`.
- **Service accounts** are both identities (instances authenticate as them) and principals (they can be granted IAM roles). Attach them to GCE instances via the `service_account` block.
- In production, prefer **Workload Identity Federation** over service account JSON keys — no long-lived credentials to rotate or leak.

---

## Cleanup

```bash
cd lab-07-gcp-provider/terraform
terraform destroy -auto-approve
```

Verify in GCP Console that all resources are removed:

- **Compute Engine > VM instances**: no `tf-lab07` instances
- **Cloud Storage > Buckets**: no `tf-lab07` buckets
- **IAM & Admin > Service accounts**: no `tf-lab07-sa` account
