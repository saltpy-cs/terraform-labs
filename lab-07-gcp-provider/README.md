# Lab 07 — GCP Provider

## Objectives

By the end of this lab you will be able to:

- Configure the GCP provider using Application Default Credentials (ADC)
- Create GCP resources: GCS bucket, GCE instance (e2-micro)
- Manage GCP IAM bindings declaratively with Terraform
- Use provider aliases to manage resources in multiple regions
- Configure multiple providers (GCP and AWS) in one Terraform configuration
- Explain how provider authentication differs between AWS and GCP

**Estimated cost:** GCE e2-micro in us-central1 is covered by the GCP Always Free tier. GCS Standard storage is ~$0.020/GB/month (essentially $0.00 for an empty bucket). The AWS provider is configured but no AWS resources are created. Keep costs at or near $0.00.

---

## Concepts

### GCP Authentication: Application Default Credentials (ADC)

GCP uses a credential lookup chain called **Application Default Credentials (ADC)**. When Terraform calls a GCP API, the Google client library walks this chain in order:

1. **`GOOGLE_APPLICATION_CREDENTIALS` environment variable** — if set, points to a service account JSON key file. Terraform uses that key directly.
2. **User credentials from `gcloud auth application-default login`** — stores OAuth2 credentials in `~/.config/gcloud/application_default_credentials.json`. This is the recommended approach for local development.
3. **Attached service account (metadata server)** — when running on GCP infrastructure (GCE, GKE, Cloud Run, etc.), credentials are retrieved from the instance metadata endpoint automatically.

For this lab, use option 2:

```bash
gcloud auth application-default login
```

This opens a browser, you authorise with your Google account, and gcloud writes credentials that Terraform can use immediately. You do not need to set any environment variables.

Contrast with AWS: AWS uses `~/.aws/credentials` (populated by `aws configure`) or environment variables (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`). The mechanisms are conceptually similar (credential file → env vars → metadata server) but the tooling differs.

### GCP Provider Configuration

The GCP provider requires three pieces of information:

```hcl
provider "google" {
  project = var.gcp_project   # GCP project ID (not name, not number)
  region  = var.gcp_region    # default region for regional resources
  zone    = var.gcp_zone      # default zone for zonal resources (GCE instances)
}
```

Unlike AWS (where region is mandatory but account ID is implicit from credentials), GCP requires you to specify the **project** explicitly. A project is the unit of billing, IAM, and resource grouping — roughly analogous to an AWS account.

### Provider Aliases

Sometimes you need multiple instances of the same provider: different regions, different projects, or different credentials. Terraform handles this with **provider aliases**.

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

Resources then reference the alias explicitly:

```hcl
resource "google_storage_bucket" "europe_bucket" {
  provider = google.europe   # uses the aliased provider
  name     = "my-europe-bucket"
  location = "EU"
}
```

Resources that do not specify `provider` use the default (unaliased) provider. This is a common pattern for multi-region architectures.

### Multi-Provider Configurations

A single Terraform configuration can have multiple *different* providers simultaneously:

```hcl
provider "google" { ... }
provider "aws"    { ... }
```

Terraform initialises and authenticates each provider independently. Resources from different providers have no special relationship — Terraform manages them through their respective APIs. This is useful when:
- Migrating workloads between clouds
- A GCP application writes to an S3 bucket
- You want to demonstrate the same concept across providers

### GCP IAM Model

GCP IAM has three components:
- **Member** — who: `user:alice@example.com`, `serviceAccount:sa@project.iam.gserviceaccount.com`, `group:...`, `allUsers`
- **Role** — what: `roles/storage.objectViewer`, `roles/editor`, custom roles
- **Resource** — where: project, bucket, dataset, etc.

Terraform provides three resources for managing IAM on a GCS bucket:

| Resource | Behaviour |
|---|---|
| `google_storage_bucket_iam_policy` | Authoritative for the entire policy. Replaces all IAM on the bucket. Dangerous — can lock you out. |
| `google_storage_bucket_iam_binding` | Authoritative for a single role. Replaces the complete member list for that role. |
| `google_storage_bucket_iam_member` | Additive. Manages a single member/role binding without affecting others. |

For most use cases, prefer `iam_member` — it is non-destructive and plays well with bindings managed outside Terraform (e.g., by the GCP console).

### GCP vs AWS Mental Model

| Concept | AWS | GCP |
|---|---|---|
| Object storage | S3 | GCS (Cloud Storage) |
| Virtual machines | EC2 | GCE (Compute Engine) |
| Identity & access | IAM | Cloud IAM |
| Billing/isolation unit | Account | Project |
| Virtual network | VPC | VPC (different model — global, not regional) |
| Subnet | Subnet (per AZ) | Subnet (per region, spans zones) |
| DNS | Route 53 | Cloud DNS |

A key GCP difference: VPCs are **global** — a single VPC spans all regions. Subnets are **regional** — they span all zones within a region. When creating a GCE instance in `us-central1-a`, you attach it to a subnet in `us-central1`, not a zone-specific subnet.

---

## Setup

### Prerequisites

- Terraform >= 1.6 installed
- `gcloud` CLI installed and configured (`gcloud init`)
- A GCP project with billing enabled
- A GCP service account email to use for the IAM demo (can be any existing SA in your project, or create one: `gcloud iam service-accounts create tf-lab07-sa --display-name "Lab 07 SA"`)

### Authenticate with GCP

```bash
gcloud auth application-default login
```

Follow the browser prompts to authorise. Verify credentials are set:

```bash
gcloud auth application-default print-access-token
```

If this prints a token, ADC is working.

### Configure Variables

```bash
cd lab-07-gcp-provider/terraform
cp ../terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and fill in:
- `gcp_project` — your GCP project ID (find it with `gcloud config get-value project`)
- `service_account_email` — a service account in your project (e.g. `tf-lab07-sa@your-project.iam.gserviceaccount.com`)

---

## Exercises

### Exercise 1 — Configure ADC

```bash
gcloud auth application-default login
```

Expected: browser opens, you authenticate, then:
```
Credentials saved to file: [/Users/you/.config/gcloud/application_default_credentials.json]
```

Verify the GCP project is accessible:
```bash
gcloud projects describe $(gcloud config get-value project)
```

Expected output: project metadata including `projectId`, `name`, `projectNumber`.

### Exercise 2 — Set Up Variables

```bash
cd /path/to/lab-07-gcp-provider/terraform
cp ../terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`. The file should look like:
```hcl
gcp_project           = "your-actual-project-id"
gcp_region            = "us-central1"
gcp_zone              = "us-central1-a"
service_account_email = "tf-lab07-sa@your-actual-project-id.iam.gserviceaccount.com"
```

### Exercise 3 — Initialise and Inspect Providers

```bash
terraform init
```

Expected output (note both providers being downloaded):
```
Initializing provider plugins...
- Finding hashicorp/google versions matching "~> 6.0"...
- Finding hashicorp/aws versions matching "~> 5.0"...
- Installing hashicorp/google v6.x.x...
- Installing hashicorp/aws v5.x.x...
...
Terraform has been successfully initialized!
```

Observe that the AWS provider is downloaded even though no AWS resources are defined. Terraform initialises all required providers declared in the `required_providers` block regardless of whether they are actively used in resources.

### Exercise 4 — Plan and Identify Provider Usage

```bash
terraform plan
```

Review the plan output carefully. Look for the `provider` attribute on each resource:

- Resources without a `provider` attribute use `provider["registry.terraform.io/hashicorp/google"]` (the default)
- The Europe bucket will show `provider["registry.terraform.io/hashicorp/google"].europe` — this is the aliased provider

Count how many resources use each provider configuration. Expected: most use the default google provider; one GCS bucket uses `google.europe`.

### Exercise 5 — Apply

```bash
terraform apply
```

Type `yes` when prompted. Expected output:
```
Apply complete! Resources: 8 added, 0 changed, 0 destroyed.

Outputs:

bucket_url         = "gs://tf-lab07-xxxx-us"
instance_self_link = "https://www.googleapis.com/compute/v1/projects/..."
instance_external_ip = "34.x.x.x"
network_id         = "projects/your-project/global/networks/tf-lab07-vpc"
```

### Exercise 6 — Verify GCS Bucket

```bash
# Using gsutil (part of gcloud SDK)
gsutil ls gs://$(terraform output -raw bucket_url | sed 's|gs://||')

# Using newer gcloud storage command
gcloud storage ls
```

Expected output from `gsutil ls`: empty output (no objects in bucket) with no error, confirming the bucket exists and you have access.

List bucket metadata:
```bash
gsutil ls -b gs://$(terraform output -raw bucket_url | sed 's|gs://||')
```

Expected:
```
gs://tf-lab07-xxxx-us/
```

### Exercise 7 — Verify GCE Instance

```bash
gcloud compute instances list
```

Expected:
```
NAME              ZONE           MACHINE_TYPE  PREEMPTIBLE  INTERNAL_IP  EXTERNAL_IP  STATUS
tf-lab07-web      us-central1-a  e2-micro                   10.0.1.x     34.x.x.x     RUNNING
```

Describe the instance in detail:
```bash
gcloud compute instances describe tf-lab07-web --zone=us-central1-a
```

Note the `machineType`, `networkInterfaces`, and `disks` sections.

### Exercise 8 — IAM Exercise

The Terraform configuration grants `roles/storage.objectViewer` to the service account on the primary bucket via `google_storage_bucket_iam_member`.

**Verify the binding exists:**
```bash
gsutil iam get gs://$(terraform output -raw bucket_url | sed 's|gs://||')
```

Expected: a JSON policy document that includes your service account with `roles/storage.objectViewer`.

**Remove the binding by editing Terraform:**

In `main.tf`, comment out the `google_storage_bucket_iam_member` resource:
```hcl
# resource "google_storage_bucket_iam_member" "viewer" {
#   ...
# }
```

Run the plan:
```bash
terraform plan
```

Expected: plan shows `1 to destroy` — the IAM binding.

Apply the removal:
```bash
terraform apply
```

Verify the binding is gone:
```bash
gsutil iam get gs://$(terraform output -raw bucket_url | sed 's|gs://||')
```

Expected: the service account no longer appears in the policy. **Terraform removed it declaratively** — you did not need to call a `gsutil iam remove-binding` command.

Restore the binding by uncommenting the resource and re-applying.

### Exercise 9 — Inspect the Europe Bucket via State

```bash
terraform state show google_storage_bucket.europe
```

Expected output:
```
# google_storage_bucket.europe:
resource "google_storage_bucket" "europe" {
    id       = "tf-lab07-xxxx-eu"
    location = "EU"
    name     = "tf-lab07-xxxx-eu"
    project  = "your-project-id"
    ...
}
```

Note: the `provider` attribute in state will reference `google.europe`. This bucket was created in the EU multi-region location via the aliased provider.

Compare with the US bucket:
```bash
terraform state show google_storage_bucket.main
```

Note the different `location` value.

### Exercise 10 — Destroy

```bash
terraform destroy
```

Type `yes`. Expected:
```
Destroy complete! Resources: 8 destroyed.
```

Verify the instance is gone:
```bash
gcloud compute instances list
```

Expected: empty (or no `tf-lab07` entries).

---

## Key Takeaways

- **ADC is the recommended authentication method for GCP.** Run `gcloud auth application-default login` once and Terraform picks it up automatically — no environment variables needed for local development.
- **Provider aliases** let you manage resources in multiple regions or projects from a single configuration. Resources reference the alias with `provider = google.europe`.
- **Multi-provider configurations** are first class in Terraform. GCP and AWS providers are independent — Terraform initialises and authenticates each separately.
- **IAM is declarative.** `google_storage_bucket_iam_member` is additive (safe for shared management); `google_storage_bucket_iam_binding` is authoritative for a role (replaces all members with that role). Use `iam_member` unless you need to own the full member list.
- **Use `force_destroy = true` on GCS buckets** so `terraform destroy` succeeds even if the bucket contains objects. Without it, GCP refuses to delete a non-empty bucket.
- **GCP VPCs are global.** A subnet is regional, not zonal. GCE instances live in a zone but attach to a regional subnet — this is different from AWS where subnets are per-AZ.

---

## Cleanup

```bash
terraform destroy
```

Verify in GCP Console that all resources are deleted:
- Compute Engine > VM instances: no `tf-lab07` instances
- Cloud Storage > Buckets: no `tf-lab07` buckets
- VPC Network > VPC networks: no `tf-lab07-vpc`
