# Terraform Labs

A progressive series of 10 hands-on labs covering Terraform from first principles to
advanced patterns. Labs 01–07 align with the **Terraform Associate** exam objectives.
Labs 08–10 introduce **Terraform Authoring and Operations Professional** topics.

## Prerequisites

Install these tools before starting:

```bash
# Terraform 1.x
brew tap hashicorp/tap
brew install hashicorp/tap/terraform

# AWS CLI
brew install awscli

# Google Cloud CLI
brew install --cask google-cloud-sdk

# Verify versions
terraform version   # should be >= 1.6
aws --version
gcloud --version
```

## Authentication Setup

### AWS

Configure credentials for a region of your choice. Labs use `us-east-1` by default.

```bash
aws configure
# AWS Access Key ID:     <your key>
# AWS Secret Access Key: <your secret>
# Default region name:   us-east-1
# Default output format: json
```

Verify access:

```bash
aws sts get-caller-identity
```

> If you use AWS SSO or named profiles, export `AWS_PROFILE=<profile>` before running
> Terraform commands.

### GCP (labs 07–08)

```bash
gcloud auth application-default login
gcloud config set project <your-project-id>
```

Verify access:

```bash
gcloud auth application-default print-access-token
```

## Cost Warning

Labs 04–09 create real AWS resources. Approximate costs if you follow each lab and
clean up immediately:

| Lab | Resources | Estimated cost |
|-----|-----------|---------------|
| 04  | EC2 t3.nano, VPC | < $0.01 |
| 05  | EC2 t3.nano, VPC (via module) | < $0.01 |
| 06  | 3× EC2 t3.nano, SGs | < $0.05 |
| 07  | GCE e2-micro (GCP free tier), GCS bucket | ~$0.00 |
| 08  | EC2 t3.nano, GCS bucket | < $0.01 |
| 09  | EC2 t3.nano × 2 workspaces | < $0.02 |
| 10  | S3 bucket | ~$0.00 |

**Always run `terraform destroy` at the end of each lab.** Leaving resources running
will incur ongoing charges.

## Lab Overview

| Lab | Topic | Providers | Cert Alignment |
|-----|-------|-----------|----------------|
| [01 - HCL Fundamentals](lab-01-hcl-fundamentals/README.md) | Blocks, lifecycle, state intro | `null`, `random` | Associate |
| [02 - Variables, Outputs, Locals](lab-02-variables-outputs/README.md) | Types, validation, data sources | `random` | Associate |
| [03 - State Management](lab-03-state-management/README.md) | Remote backends, locking, state CLI | AWS | Associate |
| [04 - AWS Provider Basics](lab-04-aws-basics/README.md) | VPC, EC2, dependencies | AWS | Associate |
| [05 - Modules](lab-05-modules/README.md) | Writing and calling modules, Registry | AWS | Associate + Pro |
| [06 - Advanced AWS](lab-06-advanced-aws/README.md) | count, for_each, dynamic blocks, lifecycle | AWS | Associate + Pro |
| [07 - GCP Provider](lab-07-gcp-provider/README.md) | GCP resources, IAM, provider aliases | AWS + GCP | Associate |
| [08 - Complex Expressions](lab-08-complex-expressions/README.md) | for, splat, templatefile, conditionals | AWS + GCP | Pro |
| [09 - Workspaces](lab-09-workspaces/README.md) | Workspace commands, env patterns | AWS | Associate + Pro |
| [10 - Testing & HCP Terraform](lab-10-testing-hcp/README.md) | terraform test, HCP Terraform, Sentinel | AWS + HCP | Pro |
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
- Built-in functions and expressions (lab 06, 08)
- Workspaces (lab 09)
- HCP Terraform basics (lab 10)

### Terraform Authoring and Operations Professional

The Professional exam goes deeper on:
- Authoring reusable modules (lab 05)
- Complex meta-arguments and expressions (labs 06, 08)
- Testing modules with `terraform test` (lab 10)
- Sentinel policy as code (lab 10)
- HCP Terraform collaboration workflows (lab 10)
- Multi-provider architectures (labs 07–08)
