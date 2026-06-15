# Terraform Labs

A progressive series of hands-on labs covering Terraform from first principles to
advanced patterns. Labs 01–07 align with the **Terraform Associate** exam objectives.
Labs 08–12 introduce **Terraform Authoring and Operations Professional** topics.

## Prerequisites

Install these tools before starting:

```bash
# Terraform 1.x
brew tap hashicorp/tap
brew install hashicorp/tap/terraform

# Google Cloud CLI
brew install --cask google-cloud-sdk

# Verify versions
terraform version   # should be >= 1.6
gcloud --version
```

## GCP Project Setup

Each learner needs a dedicated GCP project. The commands below create one named after
your local username so it is easy to identify and avoids collisions with teammates.

```bash
# Build a project ID from your username.
# GCP project IDs must be lowercase, 6–30 chars, letters/digits/hyphens, start with a letter.
PROJECT_ID="tf-labs-$(echo "$USER" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]-' | cut -c1-20)"
echo "Project ID: ${PROJECT_ID}"
```

> If this ID is already taken (project IDs are globally unique), append a short suffix:
> `PROJECT_ID="${PROJECT_ID}-01"`

```bash
# Create the project
gcloud projects create "${PROJECT_ID}" --name="Terraform Labs (${USER})"

# Link a billing account — required before any paid resources can be created.
# This lists your open billing accounts and links the first one automatically.
BILLING_ACCOUNT=$(gcloud billing accounts list \
  --filter="open=true" \
  --format="value(name)" | head -1)

if [ -z "${BILLING_ACCOUNT}" ]; then
  echo "No open billing account found."
  echo "Create one at: https://console.cloud.google.com/billing"
else
  gcloud billing projects link "${PROJECT_ID}" \
    --billing-account="${BILLING_ACCOUNT}"
  echo "Billing linked: ${BILLING_ACCOUNT}"
fi

# Set as the active project for all subsequent gcloud and Terraform commands
gcloud config set project "${PROJECT_ID}"
echo "Active project: $(gcloud config get project)"
```

## Authentication Setup

All cloud labs use GCP via Application Default Credentials (ADC).

```bash
# Authenticate your user account for ADC (opens a browser)
gcloud auth application-default login

# Verify — should print a long access token
gcloud auth application-default print-access-token

# Confirm the project is set correctly
gcloud projects describe "${PROJECT_ID}"
```

> If you use a service account instead of a user account, set
> `GOOGLE_APPLICATION_CREDENTIALS=/path/to/key.json` before running Terraform.

### Required GCP APIs

Enable these APIs once for your project before starting the labs. Each is free to enable.

```bash
gcloud services enable \
  compute.googleapis.com \
  storage.googleapis.com \
  iam.googleapis.com \
  servicenetworking.googleapis.com
```

Labs 12 also requires:

```bash
gcloud services enable \
  sqladmin.googleapis.com \
  redis.googleapis.com
```

> Individual lab READMEs note any additional APIs they need in their Setup section.

## Cost Warning

Labs 04–10 create real GCP resources. Estimated costs if you follow each lab and
clean up promptly:

| Lab | Resources | Estimated cost |
|-----|-----------|---------------|
| 04  | GCE e2-micro, VPC | ~$0.00 (free tier) |
| 05  | GCE e2-micro, VPC (via module) | ~$0.00 (free tier) |
| 06  | 3× GCE e2-micro | ~$0.00 (free tier for first, < $0.02 for others) |
| 07  | GCS bucket, GCE e2-micro, IAM | ~$0.00 |
| 08  | GCE e2-micro, GCS bucket | ~$0.00 |
| 09  | GCE e2-micro × 2 workspaces | < $0.02 |
| 10  | GCS bucket | ~$0.00 |
| 11  | Regional MIG, NLB | ~$0.05 |
| 12  | Cloud SQL REGIONAL, Memorystore STANDARD_HA | **~$0.12/hr** — destroy promptly |

GCP's free tier includes 1 e2-micro instance per month in `us-central1`, `us-west1`,
or `us-east1`. Standard GCS storage costs $0.020/GB/month — negligible for small objects.

**Always run `terraform destroy` at the end of each lab.**

## Lab Overview

| Lab | Topic | Providers | Cert Alignment |
|-----|-------|-----------|----------------|
| [01 - HCL Fundamentals](lab-01-hcl-fundamentals/README.md) | Blocks, lifecycle, state intro | `null`, `random` | Associate |
| [02 - Variables, Outputs, Locals](lab-02-variables-outputs/README.md) | Types, validation, data sources | `random` | Associate |
| [03 - State Management](lab-03-state-management/README.md) | GCS backend, locking, state CLI | GCP | Associate |
| [04 - GCP Provider Basics](lab-04-gcp-basics/README.md) | VPC, firewall, GCE, dependencies | GCP | Associate |
| [05 - Modules](lab-05-modules/README.md) | Writing and calling modules, Registry | GCP | Associate + Pro |
| [06 - Advanced GCP](lab-06-advanced-gcp/README.md) | count, for_each, dynamic blocks, lifecycle | GCP | Associate + Pro |
| [07 - IAM & Provider Aliases](lab-07-gcp-provider/README.md) | Service accounts, IAM, multi-region aliases | GCP | Associate |
| [08 - Complex Expressions](lab-08-complex-expressions/README.md) | for, splat, templatefile, conditionals | GCP | Pro |
| [09 - Workspaces](lab-09-workspaces/README.md) | Workspace commands, env patterns | GCP | Associate + Pro |
| [10 - Testing & HCP Terraform](lab-10-testing-hcp/README.md) | terraform test, HCP Terraform, Sentinel | GCP + HCP | Pro |
| [11 - Multi-Zone Resilience](lab-11-multi-zone-resilience/README.md) | RTO/RPO, Regional MIG, auto-healing, NLB, state DR | GCP | Pro |
| [12 - Active-Passive HA](lab-12-active-passive-ha/README.md) | Cloud SQL REGIONAL, Memorystore STANDARD_HA, PSA, failover pattern | GCP | Pro |
| [Practice Test](practice-test/README.md) | Full exam simulation | — | Associate + Pro |

## How to Work Through the Labs

Each lab is in its own directory. All Terraform commands are run from within the
`terraform/` subdirectory of each lab.

Each lab README has:
- **Objectives** — what you will be able to do after completing the lab
- **Concepts** — the theory behind what you're doing
- **Setup** — any prerequisites specific to this lab
- **Exercises** — step-by-step hands-on tasks
- **Key Takeaways** — what to remember for the exams
- **Cleanup** — how to destroy resources when done

## Certification Relevance

### Terraform Associate (003)

The Associate exam tests:
- IaC concepts and Terraform's workflow (lab 01)
- Variables, outputs, and data sources (lab 02)
- State and remote backends (lab 03)
- Provider configuration and resources (labs 04, 07)
- Module consumption (lab 05)
- Built-in functions and expressions (labs 06, 08)
- Workspaces (lab 09)
- HCP Terraform basics (lab 10)

### Terraform Authoring and Operations Professional

The Professional exam goes deeper on:
- Authoring reusable modules (lab 05)
- Complex meta-arguments and expressions (labs 06, 08)
- Testing modules with `terraform test` (lab 10)
- Sentinel policy as code (lab 10)
- HCP Terraform collaboration workflows (lab 10)
- Multi-provider and provider alias patterns (lab 07)
- Active-passive HA for stateful managed services (lab 12)
- Declarative vs imperative boundaries in Terraform (lab 12)
